// Cocoon overlay (Westworld-ish)
// BabylonJS via CDN in base.html.

(function(){
  const el = document.getElementById('cocoon');
  const canvas = document.getElementById('cocoonCanvas');
  const panel = document.getElementById('cocoonPanel');
  if(!el || !canvas) return;

  // Panel toggle
  function togglePanel(force){
    const open = (typeof force === 'boolean') ? force : !panel.classList.contains('open');
    panel.classList.toggle('open', open);
  }
  el.addEventListener('click', (e)=>{ e.preventDefault(); togglePanel(); });
  document.addEventListener('keydown', (e)=>{ if(e.key === 'Escape') togglePanel(false); });

  // Babylon boot (fallback silently if not available)
  function boot(){
    if(!window.BABYLON) return;

    const engine = new BABYLON.Engine(canvas, true, {
      preserveDrawingBuffer: false,
      stencil: false,
      antialias: true,
      adaptToDeviceRatio: true,
    });

    const scene = new BABYLON.Scene(engine);
    scene.clearColor = new BABYLON.Color4(0,0,0,0);

    // camera
    const camera = new BABYLON.ArcRotateCamera('cam', Math.PI/2.2, Math.PI/2.35, 2.2, BABYLON.Vector3.Zero(), scene);
    camera.attachControl(canvas, false);
    camera.lowerRadiusLimit = 2.0;
    camera.upperRadiusLimit = 2.6;
    camera.panningSensibility = 0;
    camera.wheelPrecision = 999999;

    // lighting: sculpted, minimal
    const key = new BABYLON.DirectionalLight('key', new BABYLON.Vector3(-0.6, -1.0, -0.2), scene);
    key.intensity = 1.2;
    const rim = new BABYLON.DirectionalLight('rim', new BABYLON.Vector3(0.7, -0.5, 0.9), scene);
    rim.intensity = 0.9;

    const hemi = new BABYLON.HemisphericLight('hemi', new BABYLON.Vector3(0, 1, 0), scene);
    hemi.intensity = 0.25;

    // Egg mesh (procedural for now; we can swap to glTF later)
    const egg = BABYLON.MeshBuilder.CreateSphere('egg', {diameter: 1.3, segments: 96}, scene);
    egg.scaling = new BABYLON.Vector3(0.82, 1.12, 0.82);

    // PBR metal
    const mat = new BABYLON.PBRMetallicRoughnessMaterial('eggMat', scene);
    mat.baseColor = new BABYLON.Color3(0.62, 0.64, 0.67); // grey, slightly cool
    mat.metallic = 1.0;
    mat.roughness = 0.22;

    // micro detail using a procedural noise normal-ish trick (cheap placeholder)
    // Later: real normal/roughness maps.
    const noise = new BABYLON.NoiseProceduralTexture('n', 256, scene);
    noise.brightness = 0.6;
    noise.octaves = 6;
    noise.persistence = 0.75;

    // Use noise as roughness variation
    mat.roughnessTexture = noise;

    egg.material = mat;

    // Subtle postprocess (bloom) if supported
    try{
      const pipeline = new BABYLON.DefaultRenderingPipeline('p', true, scene, [camera]);
      pipeline.bloomEnabled = true;
      pipeline.bloomThreshold = 0.85;
      pipeline.bloomWeight = 0.18;
      pipeline.bloomKernel = 42;
      pipeline.imageProcessingEnabled = true;
      pipeline.imageProcessing.contrast = 1.15;
      pipeline.imageProcessing.exposure = 1.05;
      pipeline.imageProcessing.toneMappingEnabled = true;
    }catch(err){ /* ignore */ }

    // Idle motion
    let t = 0;
    scene.onBeforeRenderObservable.add(()=>{
      const dt = engine.getDeltaTime() / 1000;
      t += dt;
      egg.rotation.y += dt * 0.22; // slow rotate
      // breathe light intensity very slightly
      key.intensity = 1.15 + Math.sin(t * 0.9) * 0.06;
      rim.intensity = 0.85 + Math.sin(t * 0.7 + 1.4) * 0.05;
    });

    engine.runRenderLoop(()=> scene.render());
    window.addEventListener('resize', ()=> engine.resize());
  }

  // wait for BABYLON to be present
  let tries = 0;
  const timer = setInterval(()=>{
    tries++;
    if(window.BABYLON){ clearInterval(timer); boot(); }
    if(tries > 80){ clearInterval(timer); }
  }, 50);
})();
