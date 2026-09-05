# Recon: Blade3D's particles — what the earlier engine did, and what carries over

*A read-only survey by a sub-agent at Christian's ask (2026-09-05, after
campaign 3's P10 pictures: "there were a few good ones and a really nice
cloud"). Kept verbatim as the recon; the decisions it feeds are in
`docs/spindrift-campaign-3.md` and the ledger. Paths are into
`~/dev/Blade3D` (Digini Blade3D, XNA 3.x, 2010).*


# Blade3D particle systems — reconnaissance report

Repo: `/home/chrisbe/dev/Blade3D` (Digini Blade3D, XNA 3.x / Shader Model 2b–3.0, dated 2010). Two generations coexist: a legacy `ParticleSystemOld` set under `Blade3D.Runtime/Particles/`, and the live system under `Blade3D.Runtime/SceneComponents/Particles/`. Everything below is the live one unless noted.

## 1. Where the code lives, and the data model

### Files

| Area | Path |
|---|---|
| Per-particle storage + sim | `/home/chrisbe/dev/Blade3D/Blade3D.Runtime/SceneComponents/Particles/ParticleSet.cs` (49 KB) |
| System owner, GPU vertex struct | `/home/chrisbe/dev/Blade3D/Blade3D.Runtime/SceneComponents/Particles/ParticleSystem.cs` |
| Per-effect parameter block | `/home/chrisbe/dev/Blade3D/Blade3D.Runtime/SceneComponents/Particles/ParticleEffect.cs` (45 KB) |
| Billboard renderer | `/home/chrisbe/dev/Blade3D/Blade3D.Runtime/SceneComponents/Particles/QuadRenderer.cs` (35 KB) |
| Mesh-instance renderer | `/home/chrisbe/dev/Blade3D/Blade3D.Runtime/SceneComponents/Particles/ParticleModelRenderer.cs` |
| Cloud | `.../Particles/VolumetricClouds.cs` + `/home/chrisbe/dev/Blade3D/Blade3D.Design/Assets/Effects/Particles/VolumetricCloud.fx` |
| God rays | `.../Particles/LightShafts.cs` + `.../Effects/Particles/LightShafts.fx` |
| Ropes / ribbons | `.../Particles/RopeParticles.cs` (22 KB) |
| Rays / streaks | `.../Particles/RayParticles.cs` (17 KB) |
| Named effects | `.../Particles/{Fire,Smoke,Explosion,Missile,Vortex,CollisionSpawn}Effect.cs` |
| Emitter shapes | `.../Particles/{Point,Cone,Cube,Cylinder,Ring,Sphere,Mesh,Bone}Emitter.cs` |
| Force/behaviour operators | `/home/chrisbe/dev/Blade3D/Blade3D.Runtime/Operators/Particles.cs` (93 KB) |
| Shaders | `/home/chrisbe/dev/Blade3D/Blade3D.Design/Assets/Effects/Particles/{Particle,VolumetricCloud,LightShafts,ParticleBillboard,ElectroStatic}.fx` |
| Presets (the real effect library) | `/home/chrisbe/dev/Blade3D/Blade3D/Templates/DefaultModule.xml` lines 3846–3857 |

### Per-particle fields — structure of arrays, CPU-side

`ParticleSet.cs:317-335`. Pure SoA, one parallel array per field, which is exactly the shape spindrift wants:

```
317  public Vector3[]    SpawnPositions        // where it was born (respawn / decal anchor)
318  public Vector3[]    EmitterPositions      // emitter pose at birth (for inherit-translation math)
319  public Vector3[]    LocalPositions
320  public Vector3[]    WorldPositions
321  public Vector3[]    LocalVelocities
322  public Vector3[]    WorldVelocities
323  public Quaternion[] LocalOrientations
324  public Quaternion[] WorldOrientations
325  public Quaternion[] AngularVelocities     // spin, integrated by NLerp from identity
326  public Vector2[]    StartSizes            // NB: 2D, width and height independent
327  public Vector2[]    EndSizes
328  public Vector4[]    Customs               // .x = per-particle random unit -> atlas frame pick
329  public Color[]      StartColors
330  public Color[]      EndColors
331  public float[]      CurrentAges
332  public float[]      Lifetimes
333  public float[]      Masses
335  public Quaternion[] EmitterOrientation
```

Plus `Parents[]` (an `ISceneItem` back-reference so a particle can follow a moving emitter).

Notable: there is **no per-particle colour/size at time t** — only start/end endpoints plus age. All interpolation happens in the vertex shader. Also **no per-particle texture-frame index**: the frame is derived from `Customs[i].x`, a random unit set once at allocation (`ParticleSet.cs:991`, `ParticleSet.cs:1014`).

### GPU vertex — 84 bytes, replicated 4× per particle

`ParticleSystem.cs:37-47`:

```
Position(12) TexCoord(8) Orientation(16, quat) StartSize(8) EndSize(8)
Custom(16) StartColor(4) EndColor(4) CurrentAge(4) Lifetime(4)
```

`QuadRenderer.cs` uses a slimmer variant with `HalfVector2` sizes and `HalfVector4` custom (`QuadRenderer.cs:30,42`). The four corner UVs are baked once into a static vertex/index buffer at `QuadRenderer.cs:92-95`:

```csharp
private static readonly HalfVector2 UV0 = new HalfVector2(-0.5f, -0.5f);
... UV1(-0.5,0.5) UV2(0.5,0.5) UV3(0.5,-0.5)
```

so the "UV" is really a signed corner offset in [-0.5, 0.5]²; the shader multiplies it by size to expand the card and uses `sign()` of it to pick the atlas cell corner.

### Per-effect parameters (`ParticleEffect.cs:37-266`)

`Material`, `SpawnRate` (default 30/s), `StartColor`/`EndColor`, `StartAlpha`/`EndAlpha`, `StartSize`/`EndSize` (Vector2), `Min/MaxVelocity`, `Min/MaxAge`, `Min/MaxMass`, `Min/MaxSpin` (quaternion), `Min/MaxSpawnOrientation`, `Spawn`, `SpawnMode` (`Periodic` | `AllAtOnce`, `ParticleEffect.cs:21-32`), `BlendMode`, `GameGraph` (the operator graph that adds forces), `SizeScale`/`ColorScale`/`VelocityScale`/`SpinScale`, `SimulationSpeed`, `Gravity`, `ViscousDrag`, `Simulation`, `Model` (mesh particles).

The scale knobs are folded in at spawn, not per frame (`ParticleEffect.cs:837-871`) — note that **alpha overrides the colour's own alpha channel** rather than multiplying:

```csharp
858  Vector4 startColor_Vec = startColor.ToVector4();
859  startColor_Vec.X *= colorScale; ...
863  startColor_Vec.W = this.StartAlpha.Value;
```

Per-system (`ParticleSystem.cs:60-176`): `Simulate`, `SimulationSpeed`, `MaxParticles` (default 1024, capped 1024), `Gravity`, `ViscousDrag`, `Render`.

Spawn accumulator, `ParticleEffect.cs:1020-1025`:

```csharp
set.SpawnAccumulator += this.SpawnRate.Value * RenderContext.DeltaTime * obj.SimulationSpeed * set.SimulationSpeed;
spawnCount = (int)set.SpawnAccumulator;
set.SpawnAccumulator -= spawnCount;
```

### Simulation

`ParticleSet.FullIntegrate` (`ParticleSet.cs:456-789`) is unsafe-pointer semi-implicit Euler over the SoA arrays, single-threaded, CPU. Age first for an early out (`ParticleSet.cs:553`), then:

```csharp
596  gravForce = mass * gravity;
600  dragForce = -velocity * viscousDrag;
608  velocity += (linearForce * invMass) * deltaTime;
618  position += velocity * deltaTime;
622  QuaternionOperators.NLerp(ref quatIdentity, ref *pCurAngularVel, deltaTime, out rotation);
623  this.LocalOrientations[i] *= rotation;
```

Dead particles are compacted by a write-index sweep, so the array stays dense. Average position and velocity are accumulated for free during the sweep (`ParticleSet.cs:636-643`) — cheap and used by follow/steer operators.

Forces beyond gravity/drag come from a node graph run **before** integration (`ParticleSet.cs:437-454`), from `Operators/Particles.cs`:

- Physics: Apply Force, Attract Or Repel, Damping, Gravitate, Match Particle Velocity, Match Particle Rotational Velocity, **Turbulence**
- Primitives: Avoid, Collide Particles, **Jet**, **Sink**
- Effects: **Explosion**, **Vortex**
- Settings: Change Material By Age, Change Model By Age, Copy Particle Set Settings, Modify Global/Individual Settings, Set Particle Size, Target Color

Turbulence (`Operators/Particles.cs:874-959`) is 3-tap Perlin with decorrelated offsets, normalised then scaled — a clean recipe worth stealing verbatim:

```csharp
918  pForce.X = NoiseOperators.Turbulence(pPosition.X,       pPosition.Y,       pPosition.Z) * 2f - 1f;
919  pForce.Y = NoiseOperators.Turbulence(pPosition.Y + 13f, pPosition.Z + 78f, pPosition.X + 53f) * 2f - 1f;
920  pForce.Z = NoiseOperators.Turbulence(pPosition.Z + 97f, pPosition.X + 47f, pPosition.Y + 14f) * 2f - 1f;
922  pForce.Normalize();
```

## 2. Rendering technique

**Billboarding.** Screen-aligned, built in the vertex shader, `Particle.fx:278-300`:

```hlsl
278  if (FaceCamera) {
279      pos = mul(input.Position, World);
282      float3 forward = normalize(CameraPos - pos);
283      float3 right   = normalize(cross(forward, View._m01_m11_m21));
284      float3 up      = normalize(cross(right, forward));
286      float angle = quatGetAngle(orientation);      // roll about view vector
293      float4 rot = quatAxisAngle(forward, angle);
295      right = quatRotateVec(right, rot);
296      up    = quatRotateVec(up, rot);
298      pos += right * scale.x;
299      pos += up    * scale.y;
300  }
```

It is *point-facing* (`normalize(CameraPos - pos)`, per-vertex, not view-plane-parallel), with the up vector taken from the view matrix's second row so the card stays roll-stable, then rolled by the particle's own spin quaternion. `FaceCamera=false` (`Particle.fx:301-305`) gives a free-oriented card driven entirely by the quaternion — that is how decals and footprints are laid flat (`DefaultModule.xml:3557,3560`).

**There is no velocity-stretched card and no axis-locked mode anywhere.** I grepped the whole particle tree and shader set for stretch/velocity-align/axis-lock; nothing. Streaks are faked instead by giving the card a non-uniform `Vector2` size and letting spin orient it — e.g. the legacy Rays preset `StartSize "0.25,0.25"` → `EndSize "2.0,0.25"` (`Blade3D.Runtime/Particles/Rays.cs:29-30`). This is the single biggest gap versus what spindrift wants.

**Sorting — this is the weak spot.** There is **no per-particle depth sort at all**. Sorting happens only at renderable granularity, i.e. one entry per *particle set*, back-to-front, in `SceneComponents/SceneGraph/SceneRenderer.cs:35-89`:

```csharp
67   double dist = squareDistToRenderable * squareInvFar;
72       if (renderable.UsesTransparency) weight -= w; else weight += w;
77   if (renderable.UsesTransparency) weight += 100000000.0 + renderable.RenderLayer * 100.0f;
89   Array.Sort(this.SortWeights, this.Renderables, 0, count);
```

Particles register at `RenderLayer = 40` (`QuadRenderer.cs:220`). Within a set, particles are emitted to the vertex buffer in **allocation order**. To hide it, every particle shader uses the classic two-pass alpha-test trick, documented in the comments of `ParticleBillboard.fx:156-182` and implemented in `Particle.fx:373-411`:

- `FullOpaquePass` — `AlphaBlendEnable=false`, `AlphaFunc=GreaterEqual, AlphaRef=240`, `ZWriteEnable=false`, `CullMode=NONE`: draws only near-opaque cores.
- `TransparentPass` — `AlphaBlendEnable=true, SrcBlend=SrcAlpha, DestBlend=One`, `AlphaFunc=Less, AlphaRef=240`: draws the fringes additively, where order does not matter.

Note both passes have `ZWriteEnable=false`, so the first pass does not actually give depth ordering — the trick is only half-applied here; the real ordering work is the additive fringe.

**Blend modes** — six, as CPU render-state delegates, `ParticleSet.cs:19-27` and `ParticleSet.cs:791-845`:

| Mode | Op | Src | Dest |
|---|---|---|---|
| `Normal` (0) | Add | SrcAlpha | InvSrcAlpha |
| `Emissive` (1, default) | Add | One | One |
| `AlphaEmissive` (2) | Add | SrcAlpha | One |
| `Subtractive` (3) | ReverseSubtract | SrcAlpha | One |
| `Max` (4) | Max | InvSrcAlpha | SrcAlpha |
| `Min` (5) | Min | InvSrcAlpha | SrcAlpha |

Applied inside the draw callback at `QuadRenderer.cs:630` (`set.BlendOp()`), so it overrides whatever the .fx technique declared. Every pixel shader ends with `color.rgb *= color.w * depthFade` (`Particle.fx:367`) — i.e. the shader **premultiplies by alpha itself**, which is what makes `SrcBlend=One` / additive behave sanely and is why `Emissive` is the default.

**Soft particles** — `Particle.fx:352-367`, identical code in `VolumetricCloud.fx:416-432` and `LightShafts.fx:445-457`:

```hlsl
352  float depthFade = 1;
354  if (SoftParticles) {
355      float2 screenCoords = 0.5 * (input.ScreenTex.xy / input.ScreenTex.w) + 0.5;
356      screenCoords.y = 1 - screenCoords.y;
358      float sceneDepth    = tex2D(DepthSampler, screenCoords).r * ViewRange;
359      float particleDepth = length(input.ViewPos);
361      float depthRange = abs(sceneDepth - particleDepth);
363      depthFade = saturate(depthRange / DistanceThreshold);
364      depthFade = pow(depthFade, FallOff);
365  }
367  color.rgb *= color.w * depthFade;
```

Parameter names are **`DistanceThreshold`** (0–10, default 0.5 in `Particle.fx:106-111`, **2.5** in `VolumetricCloud.fx:120-127`) and **`FallOff`** (1–10, default 1.5). Two things matter for porting: the depth is **radial view distance** (`length(viewPos)`, not linear z), and the scene depth is normalised, rescaled by `ViewRange`. Also, `abs()` means a particle *behind* geometry fades too, not just in front — sloppy but visually forgiving.

**Lighting.** Standard particles are **completely unlit** — texture × interpolated vertex colour, nothing else (`Particle.fx:330-347`). There is no normal, no ambient, no sun term. The apparent volume comes entirely from the artwork: `Particle_COLOR.png` is a **pre-shaded grey sphere with a baked highlight at upper-left** (128×128 RGBA), so every puff carries fixed, baked lighting. The two exceptions:

- `LightShafts.fx:471-503` does a real **shadow-map lookup** on the particle — the only shadowed particle in the engine (details in §4).
- `ElectroStatic.fx` has a `NORMAL` input and a `Specular Power` (`ElectroStatic.fx:38,60`) — but it's a mesh shader, not a billboard.

**Textures / flipbooks.** A single texture atlas with `AtlasCount` (float2, up to 10×10) — `Particle.fx:57-72`. Cell UV selection, `Particle.fx:186-198`:

```hlsl
191  int2 atlasPos = int2(subTextureIndex % atlasCount.x, subTextureIndex / atlasCount.x);
192  float2 subTextureSize = 1.0f / atlasCount;
195  uv = uvCenter + 0.5f * subTextureSize * sign(baseUV);
196  uv = 1 - uv.xy;
```

Two modes, `Particle.fx:240-266`:

- `Animated = false` (default): a **static random frame per particle**, biased by `AtlasProbabilityCurve`: `probability = pow(input.Custom.x, 1.0f / AtlasProbabilityCurve)` — a rank-biased sheet pick so you can weight one puff shape over another. Very cheap variety.
- `Animated = true`: a genuine **flipbook with cross-fade between adjacent frames**. `Particle.fx:246-255` computes `bf`, derives `subTextureIndex`, emits a second UV set for frame+1, and passes `CrossBlend`; the PS at `Particle.fx:342` does `color = lerp(tex0, tex1, input.CrossBlend)`. No motion vectors — straight linear cross-dissolve.

Size interpolation has a per-axis easing exponent, `Particle.fx:268`:

```hlsl
float2 size = lerp(startSize, endSize, pow(blendFactor, AtlasScaleCurve));
```

and a spawn fade-in, `Particle.fx:316-319`:

```hlsl
float lerpvalue = saturate(age / SpawnFade);   // SpawnFade default 0.5s
lerpvalue = smoothstep(0, 1, lerpvalue);
color.w *= lerpvalue;
```

Age blend itself is `smoothstep(0,1, age/lifetime)` under SM3.0, raw linear on SM2 (`Particle.fx:230-235`).

**Noise/turbulence at shading time** exists only in the cloud and light-shaft shaders (3D volume texture, §3). **GPU simulation: none.** All simulation is CPU; the GPU only expands and interpolates.

## 3. The CLOUD effect

This is `VolumetricClouds` + `VolumetricCloud.fx`, and it deserves the reputation. It is **not** ray-marched and **not** slices through a box. It is a *recursive box-subdivision that seeds camera-facing puff cards along a depth ramp, shaded by a 3D noise volume with a vertical top/bottom colour gradient and an animated drifting "dust" layer*.

### Construction, CPU side — `VolumetricClouds.cs`

Parameters (`VolumetricClouds.cs:19-74`): `SplitCount` (1–15, default 2), `SplitBias` (0.1–4, default 0.8), `Boxes` (1–30, default 10), `Seed` (0.1–30, default 20), `InitialBoxMin`/`Max` (default ±2), `DrawBoxes` (debug), `Refresh`.

Step 1 — build a cluster of jittered, overlapping AABBs by recursive random inflation of the initial box, seeded by a Mersenne Twister so the cloud is deterministic and re-rollable (`VolumetricClouds.cs:188-224`):

```csharp
195  float x1 = this.Twister.NextFloat() * random;   // ... y1, z1, x2, y2, z2
209  Vector3 maxAddition = new Vector3(x1, y1, z1);
210  Vector3 minAddition = new Vector3(x2, y2, z2);
212  newMax = max + maxAddition;
213  newMin = min - minAddition;
215  BoundingBox newBoundingBox = new BoundingBox(newMin, newMax);
217  this.BoundingBoxList.Add(newBoundingBox);
219  this.SliceBoundingBox(bounds, seed);
```

The union of the boxes becomes the scene item's AABB (`VolumetricClouds.cs:174-182`).

Step 2 — for each box, walk a depth ramp along the box's dominant axis and drop **one particle per split**, its size lerped between the near-face and far-face cross-sections (`VolumetricClouds.cs:387-439`):

```csharp
418  Vector2 nearSize = new Vector2((corners[2]-corners[0]).Length(), (corners[1]-corners[0]).Length());
419  Vector2 farSize  = new Vector2((corners[6]-corners[4]).Length(), (corners[5]-corners[4]).Length());
420  Vector3 startPoint = sceneItem.World.Translation - min + sceneItem.World.Forward * near;
421  Vector3 endPoint   = sceneItem.World.Translation + max + sceneItem.World.Forward * far;
426  for (int i = 0; i < splitCount; i++) {
428      float blendFactor = invSplitCount * i;
429      blendFactor = (float)Math.Pow(blendFactor, splitBias);   // non-uniform depth distribution
430      blendFactor = 1.0f - blendFactor;
432      Vector3 centerPoint = Vector3.Lerp(startPoint, endPoint, blendFactor);
433      Vector2 size        = Vector2.Lerp(nearSize, farSize, blendFactor);
436      this.Effect.StartSize = size;
437      this.Effect.EndSize   = size;
438      this.Effect.SpawnParticlesAtPosition(set, 1.0f, centerPoint, centerPoint, this.SceneItem);
439  }
```

Step 3 — freeze it (`VolumetricClouds.cs:442-446`):

```csharp
442  set.InheritEmitterRotation = true;
443  set.InheritEmitterTranslation = true;
444  set.AllowDeath = false;
446  this.UpdateParticles = false;
```

So it is a **static, one-shot population** — `Boxes × SplitCount` cards (default 10 × 2 = 20, up to 30 × 15 = 450), never re-simulated, glued to the object's transform. The only motion is the slow spin from `MinSpin/MaxSpin = ∓10°` in the preset, and the animated noise in the shader. `SplitBias` is the perceptual knob: it biases card density toward the near or far face so silhouettes read as thicker at one end.

Preset (`DefaultModule.xml:3853`):

```
CloudEffect: Material=Particles/VolumetricCloud
  StartAlpha=0.78 EndAlpha=0.78  StartColor=63,63,63,200  EndColor=63,63,63,200
  MinVelocity=0 MaxVelocity=0  MaxSpawnOrientation=180°  SpawnMode=0
  BlendMode=0 (Normal / SrcAlpha·InvSrcAlpha)   MinSpin=-10° MaxSpin=+10°
```

Note it uses **Normal alpha blending**, not the engine-default additive — clouds occlude, they do not glow. Colour is a flat dark grey (63,63,63) that the shader then re-tints.

Material (`DefaultModule.xml:3565`): `VolumetricCloud.fx` with `DiffuseTexture = /Textures/Particles/LightShaft_COLOR.vtf` (256×256, uncompressed BGRA, no mips) — a soft radial falloff card, shared with the light shafts.

### Shading — `VolumetricCloud.fx`

Shader-level defaults (`VolumetricCloud.fx:83-187`): `SizeScale {1.6,1.6}`, `ColorScale 0.32`, `ColorBias 0.76`, `NoiseScale 28.5`, `DustScale 16.0`, `NoiseRate 4.0`, `DustColor {1,1,1}`, `TopColor {1,1,1}`, `BottomColor {0.2,0.2,0.2}`, `DistanceThreshold 2.5`, `FallOff 1.5`, `DustEffect = true`.

Vertex shader is the standard billboard, with two changes: the card is inflated by `SizeScale` (`VolumetricCloud.fx:337-338`), and it exports **world position** so the noise is sampled in world space and the cloud is coherent across cards (`VolumetricCloud.fx:373`).

The whole cloud look is these six lines, `VolumetricCloud.fx:394-413`:

```hlsl
394  color = tex2D(DiffuseTextureSampler, input.UVSet.xy);
395  color *= input.Color;

399  float3 pixelPos = input.PixelPosition.xyz;
400  float4 noiseColor = tex3D(VolumeMapSampler, pixelPos / NoiseScale);

402  if (DustEffect) {
404      float3 dustPos = pixelPos + float3(0.0f, -Time * NoiseRate, 0.0f);
405      float4 dust = tex3D(VolumeMapSampler, dustPos / DustScale);
406      color.xyz = max(color.xyz, dust.x * DustColor * 0.5f);
407  }

409  color.xyz += noiseColor;

411  float3 cloudColor = lerp(TopColor, BottomColor, input.UVSet.y);

413  color.rgb = pow(color.rgb * cloudColor, ColorBias);
```

then the shared soft-particle fade and premultiply (`VolumetricCloud.fx:416-432`).

Reading it as a recipe:

1. **Base card**: soft radial sprite × per-particle colour (already scaled by `ColorScale 0.32` in the VS at line 387 — deliberately dark, so the additive noise has headroom).
2. **Static structure**: `tex3D(noise, worldPos / 28.5)` **added**. Because it is sampled in *world* space, overlapping cards agree on where the lumps are, which is what defeats the "I can see individual sprites" tell. This is the key trick.
3. **Drifting dust**: a second, finer octave (`/16.0`) scrolling **downward** at `NoiseRate` (`-Time * 4.0` on Y), combined with `max()` rather than add — so it only ever brightens, producing wispy moving highlights without washing out.
4. **Vertical gradient**: `lerp(TopColor, BottomColor, uv.y)` — per-card, using the card's own V coordinate, so **every puff is individually lit bright-on-top, dark-underneath**. This is a fake self-shadowing term and it is the cheapest, highest-value part of the whole effect. Default is white → 0.2 grey, a 5:1 ratio.
5. **Tone curve**: `pow(color * cloudColor, 0.76)` — a gamma lift that crushes the dark cores and makes the fringes bloom.

The noise volume is `/home/chrisbe/dev/Blade3D/Blade3D.Design/Assets/VolumeTextures/Samples/NoiseVolume.dds` — **128×128×128, 8-bit luminance, 2,097,152 bytes**, wrap-addressed on all three axes with trilinear filtering (`VolumetricCloud.fx:240-251`).

One caveat if porting literally: `color.xyz += noiseColor` adds a `float4` to a `float3` — the compiler truncates, so it adds `.xyz` of a luminance texture, i.e. a uniform grey lift. Fine, but the intent was probably `noiseColor.x`.

## 4. Every named effect

Preset library is `DefaultModule.xml:3846-3857`; behaviour classes are the `*Effect.cs` files.

| Effect | Where | What makes it work |
|---|---|---|
| **CloudEffect** | `xml:3853`, `VolumetricClouds.cs`, `VolumetricCloud.fx` | Seeded box cluster → static puff cards + world-space 3D noise + per-card vertical gradient + scrolling dust. §3. |
| **LightShaftEffect** | `xml:3855`, `LightShafts.cs`, `LightShafts.fx` | Cards stacked across the **light's frustum** (near→far, `SplitCount` 30, `SplitBias` 2.0), sized to the frustum cross-section, then **shadow-mapped per pixel** so the shaft is carved by occluders. `ColorScale=0.08`. |
| **FireEffect** | `xml:3847`, `FireEffect.cs` | Upward velocity (Y 1.0) + `Damping{0,1,0}, MaxVel 10` clamp so flames rise then stall; size 2→(3.5,5) grows taller than wide; alpha 0.392→0; additive; `ColorScale 1.5` overdrive on `Fire1_COLOR`. |
| **SmokeEffect** | `xml:3848`, `SmokeEffect.cs` | Same skeleton, slower (`Damping{0,2,0}, MaxVel 3`), long life (1–6 s), size 2→(5,6), heavy spin (±90°/s) so puffs churn, warm-grey 87,85,81 → cold 38,38,38. |
| **MissileEffect** | `xml:3849`, `MissileEffect.cs` | The good one: **two particle subsets** and a `ChangeMaterialByAge` operator at `AgeThreshold=1` (`xml:111`) that promotes fire → smoke mid-flight, with `CopySettings` keeping the two sets coherent. `SimulationSpeed=4`. |
| **ExplosionEffect** | `xml:3850`, `ExplosionEffect.cs`, op at `Operators/Particles.cs:1393` | `SpawnMode=AllAtOnce` (100 at once), then a **Gaussian shock-wave ring** expanding at `speed` that both accelerates *and inflates* particles as it passes. |
| **VortexEffect** | `xml:3851`, `VortexEffect.cs`, op at `Operators/Particles.cs:1497` | Tornado: `tightnessExponent` shapes the silhouette (1 = cone, >1 curves inward), `maxRadius` cylinder of influence, separate `inSpeed`/`upSpeed`/`aroundSpeed`. Cyan→red over life. |
| **CollisionEffect** | `xml:3852`, `CollisionSpawnEffect.cs` | Physics-driven: spawns 2 smoke puffs at each contact point, throttled to 0.01 s (`xml:3588`). |
| **DecalEffect** | `xml:3856` | `FaceCamera=False` + `IsDecal` + 3×3 `BulletHoles` atlas (1024²), 30 s life, `AtlasProbabilityCurve` picks a random hole. |
| **FootPrintEffect** | `xml:3857` | Same mechanism, `FootPrints_COLOR` 3×3 atlas, 15 s life. |
| **RopeParticles** | `RopeParticles.cs` | Verlet-ish chain: `RopeLength`, `Damping` (default 0.94), `Ropes` count, `ParticlesPerRope` — particles constrained into strands. |
| **RayParticles** | `RayParticles.cs`, legacy `Particles/Rays.cs` | Streaks via non-uniform card: `StartSize 0.25,0.25` → `EndSize 2.0,0.25`, plus `Intensity`/`Magnitude`/`Epsilon`/`Axis`. |
| **ElectroStatic** | `Effects/Particles/ElectroStatic.fx` | Mesh-based crackle: scrolling 3D noise + specular, `NoiseRate`/`NoiseScale`/`SpecularPower`. |
| **Rainfall** (adjacent) | `Effects/ImageProcessing/Rainfall.fx` | Not particles — a full-screen lens shader with a rain mask + normal map. Worth knowing it exists so you do not rebuild rain as particles. |

### Top five worth carrying over

1. **CloudEffect** — the world-space-noise-plus-per-card-vertical-gradient combination is the actual insight, and it is ~8 lines of shader. It converts a handful of cards into something that reads as volume. Directly applicable, and spindrift's G-buffer makes it *better*: the fake `lerp(TopColor,BottomColor,uv.y)` can become a real sun-direction term.
2. **LightShaftEffect** — the only effect here that samples a shadow map per particle pixel. spindrift already has a sun shadow map, so this is nearly free, and volumetric shafts sell a path-traced scene enormously.
3. **MissileEffect's `ChangeMaterialByAge`** — not a look, a *mechanism*: one emitter, two appearances, promoted by age. Cheap way to get fire→smoke, spark→ember, splash→mist without authoring two systems.
4. **ExplosionEffect's Gaussian shock wave** — a single closed-form force that gives a genuinely wave-like expansion rather than a uniform radial burst, and it drives size as well as velocity. Self-contained, ~15 lines.
5. **Turbulence operator** — the 3-tap decorrelated-Perlin-then-normalise force. It is what stops every smoke column looking like a fountain. Cheap on CPU, and it composes with everything else.

Honourable mention: the **`AtlasProbabilityCurve` random-frame pick**. One random number per particle, no animation cost, and it eliminates the "all my puffs are the same puff" tell. Nearly free to implement.

## 5. Texture assets

All under `/home/chrisbe/dev/Blade3D/Blade3D.Design/Assets/Textures/`. `.vtf` is Valve Texture Format v7.2 (the engine's runtime container); PNG/TGA sources sit alongside some of them.

| File | Size | Format | Used by | Content |
|---|---|---|---|---|
| `Particles/Particle_COLOR.png` / `.vtf` | 128×128 | RGBA8 / VTF 8 mips | generic | **Pre-shaded grey sphere with baked upper-left highlight** — the fake-lit puff |
| `Particles/Smoke_COLOR.png` / `.vtf` | 64×64 | RGBA8 / VTF 7 mips | Smoke | Soft irregular wispy blob, alpha-cut |
| `Particles/WhiteSmoke1_COLOR.vtf` | 256×256 | VTF, **no mips**, uncompressed BGRA (262,352 B) | `Materials/Particles/Smoke` | Main smoke puff |
| `Particles/WhiteSmoke2_COLOR.vtf` | 256×256 | VTF, no mips | alt smoke | Second puff variant |
| `Particles/Fire1_COLOR.vtf` | 256×256 | VTF, no mips | Fire, Missile | Flame lick |
| `Particles/LightShaft_COLOR.vtf` | 256×256 | VTF, no mips | **LightShafts *and* VolumetricCloud** | Soft radial falloff card |
| `Particles/BlueBubble_COLOR.tga` / `.vtf` | 256×256 | TGA RGBA32 / VTF 9 mips | Explosion, Vortex | Round bubble w/ rim |
| `Decals/BulletHoles_COLOR.vtf` | 1024×1024 | VTF 11 mips | DecalEffect | **3×3 atlas**, ~341 px cells |
| `Decals/FootPrints_COLOR.vtf` | 1024×1024 | VTF 11 mips | FootPrintEffect | **3×3 atlas** |
| `VolumeTextures/Samples/NoiseVolume.dds` / `.vtf` | **128×128×128** | DDS 8-bit luminance, 2 MB | Cloud, LightShafts, ElectroStatic | Tiling 3D noise |
| `System/Black_COLOR.vtf`, `White_COLOR.vtf` | — | — | depth/shadow sampler defaults | placeholders |

**No normal maps for any particle** — the "normal-mapped smoke puff" does not exist here; the shading is baked into `Particle_COLOR`. **No true flipbook sheets shipped either**: the only atlases are the two 3×3 decal sheets, and both use random-frame-per-particle rather than animation. The `Animated` cross-fade path in `Particle.fx:240-255` is implemented but unused by any shipped preset.

## What maps onto spindrift / matryoshka

For each recommendation, what it needs from your architecture.

### 1. Cloud / puff volume — *port this first*

- **Per-row (sim):** position, size (2-vector, not scalar — Blade3D's non-uniform card is load-bearing), roll angle, random unit `u ∈ [0,1)` for frame pick. Age/life only if you want them to evolve; the Blade3D cloud is static (`AllowDeath=false`).
- **Per-kind (appearance):** `TopColor`, `BottomColor`, `ColorScale` (0.32), `ColorBias` (0.76 gamma), `NoiseScale` (28.5), `DustScale` (16.0), `NoiseRate` (4.0), `DustColor`, `SizeScale` (1.6).
- **Texture:** one soft radial card, 256², alpha only is enough. Plus a **128³ single-channel tiling noise volume** — this is a genuinely new asset requirement, ~2 MB, and the effect does not work without it.
- **Blend:** straight alpha (`SrcAlpha`/`InvSrcAlpha`), with the shader premultiplying (`rgb *= a`) as Blade3D does.
- **Lighting term:** replace the fake `lerp(Top,Bottom,uv.y)` with a real one. You have sun direction, a shadow map, and irradiance — so: `lerp(Bottom, Top, saturate(dot(cardNormalApprox, sunDir)))` where the approx normal is reconstructed from the card's UV as a hemisphere, times sun visibility from the shadow map, plus your irradiance as the ambient term. This is strictly better than the original and is the main reason to rebuild rather than copy.
- **Velocity-stretched card:** not needed.
- **Not yet in the raster pass:** a **3D texture binding** for the noise volume, and world-space position interpolated to the fragment shader (Blade3D exports it at `VolumetricCloud.fx:373`). Both are small additions.

### 2. Light shafts

- **Per-row:** position only — the cards are static and frustum-aligned.
- **Per-kind:** `SplitCount` (30), `SplitBias` (2.0), `ColorScale` (0.08), `DustColor`, `NoiseRate`.
- **Texture:** the same soft radial card + the same noise volume. No new assets.
- **Blend:** additive (`SrcAlpha`/`One`).
- **Lighting term:** **the sun shadow map, sampled per fragment.** This is the whole effect. Blade3D's version (`LightShafts.fx:471-503`) is a hard binary compare; yours should be a soft/filtered lookup.
- **Not yet in the raster pass:** the emitter needs the **sun's frustum corners** to place cards, i.e. the raster pass must be handed the shadow-map view-projection *and* the light frustum bounds, not just the texture.

### 3. Age-driven appearance promotion (from MissileEffect)

- **Per-row:** age, plus a **kind index** that the sim can rewrite.
- **Per-kind:** an `age_threshold` and a `promotes_to: kind` link.
- **Texture / blend / lighting:** none of its own — it inherits from whichever kind it points at. But note this means **a single population can span two blend modes**, so your draw must bucket by kind after sorting, or sort within kind. That is a real structural constraint worth deciding early.
- **Not yet in the raster pass:** possibly nothing, if you already bucket draws by kind. If you sort one flat list and draw it in one call, this forces a change.

### 4. Explosion shock wave

- **Per-row:** position, velocity, age, end-size (the operator *writes back* into end-size at `Operators/Particles.cs:1454-1455`, so size must be mutable, not a per-kind constant).
- **Per-kind:** `speed`, `magnitude`, `spread`, `softening`, `start_time`, `scale`.
- **Texture:** reuse the puff card; the shape is entirely in the motion.
- **Blend:** additive early, alpha late — which is exactly case 3 above, so these two compose.
- **Lighting term:** emissive, so none — but it should **write into your bloom/emissive channel** if you have one.
- **Not yet in the raster pass:** nothing.

### 5. Turbulence

- **Per-row:** position, velocity, mass.
- **Per-kind:** `force_scale` (3-vector), `noise_scale` (3-vector), `time_speed`.
- **Texture / blend / lighting:** none.
- **Not yet:** nothing — pure CPU sim, drops straight into matryoshka. Needs a Perlin/simplex source, and note Blade3D's `time` term is `DeltaTime * timeSpeed` (`Operators/Particles.cs:894`), which is a **bug** — it should be accumulated time, not the frame delta, or the noise field does not actually evolve. Fix on port.

### Cross-cutting gaps in Blade3D that spindrift should not inherit

- **Per-particle depth sorting.** Blade3D has none — only per-set. Your brief says "sorted", so you are already ahead; but be aware that every Blade3D shader assumes the two-pass alpha-test crutch (`ParticleBillboard.fx:156-182`), and once you sort properly you can drop the `FullOpaquePass` entirely and halve the draw cost.
- **Velocity-stretched cards.** Genuinely absent. Any spark, rain, streak or trail you want will need a per-row velocity fed to the card-expansion step and a per-kind `stretch_scale` — there is no prior art here to copy.
- **Soft-particle depth basis.** Blade3D compares `length(viewPos)` against a rescaled non-linear depth and takes `abs()`. Against a path-traced G-buffer you almost certainly have true linear view depth, so use `saturate((sceneZ - particleZ) / threshold)` **without** `abs()` — one-sided — which fixes the artefact where a particle behind a wall fades instead of being hidden.
- **Real lighting.** Every standard particle is unlit with baked shading in the texture. Since you have albedo, normals, irradiance and a sun shadow map, the single highest-value upgrade is a per-kind `lighting_mode` (unlit / hemisphere-approx / sun+shadow) — the cloud's vertical gradient is a crude hand-rolled version of exactly that, and getting it right is what will make these effects sit in a path-traced frame rather than float on top of it.