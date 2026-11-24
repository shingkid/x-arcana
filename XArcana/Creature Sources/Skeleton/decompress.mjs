// Node dependencies: @gltf-transform/core, @gltf-transform/extensions, meshoptimizer.
// KTX tool: Khronos KTX-Software 4.4.2, `ktx extract --transcode rgba8`.
import { createRequire } from 'node:module';
import { writeFile, readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(process.env.GLTF_TOOL_PACKAGE || '/tmp/ember-gltf-tools/package.json');
const { NodeIO } = require('@gltf-transform/core');
const { ALL_EXTENSIONS } = require('@gltf-transform/extensions');
const { MeshoptDecoder } = await import(require.resolve('meshoptimizer'));
const dir = path.dirname(fileURLToPath(import.meta.url));
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({'meshopt.decoder': MeshoptDecoder});
const doc = await io.read(path.join(dir, 'tevy-skeleton-v1.glb'));
for (const [i, texture] of doc.getRoot().listTextures().entries()) {
 const ktx = path.join(dir, `texture-${i}.ktx2`);
 const png = path.join(dir, `texture-${i}.png`);
 await writeFile(ktx, texture.getImage());
 execFileSync(process.env.KTX_TOOL, ['extract', '--transcode', 'rgba8', ktx, png], {stdio:'inherit'});
 texture.setImage(await readFile(png)).setMimeType('image/png');
}
for (const ext of doc.getRoot().listExtensionsUsed()) {
 if (['KHR_texture_basisu','EXT_meshopt_compression'].includes(ext.extensionName)) ext.dispose();
}
await io.write(path.join(dir, 'skeleton-uncompressed.glb'), doc);
console.log('Decoded mesh and textures for Blender.');
