import SceneKit
import AppKit
struct Combat { struct Identity: Decodable { let id: String; let name: String; let image: String } }
final class PortraitPreviewNode: SCNNode { var identityID = "" }
@main struct FacePreview {
 static func main() throws {
 let scene=SCNScene();scene.background.contents=NSColor(calibratedRed:0.06,green:0.07,blue:0.065,alpha:1)
 let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.zNear=0.02;camera.camera!.fieldOfView=42;camera.camera!.wantsHDR=true;camera.camera!.exposureOffset = -0.65;scene.rootNode.addChildNode(camera)
 camera.position=SCNVector3(0,1.65,4.8)
 let roster=try JSONDecoder().decode([Combat.Identity].self,from:Data(contentsOf:assetBundle.url(forResource:"roster",withExtension:"json",subdirectory:"NPCPortraits")!))
 var enemies:[PortraitPreviewNode]=[]
 for (i,identity) in roster.prefix(8).enumerated() { let node=PortraitPreviewNode();node.identityID=identity.id;node.simdScale=ZombieAppearance.scale(for:i);node.addChildNode(ZombieAppearance.make(identity:identity,index:i));scene.rootNode.addChildNode(node);enemies.append(node) }
 let ambient=SCNNode();ambient.light=SCNLight();ambient.light!.type = .ambient;ambient.light!.intensity=25;scene.rootNode.addChildNode(ambient)
 let key=SCNNode();key.light=SCNLight();key.light!.type = .omni;key.light!.intensity=70;key.position=SCNVector3(-1,2.5,2);scene.rootNode.addChildNode(key)
 let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera
 let output=URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Previews").path + "/"
 for enemy in enemies.prefix(4) {
  enemies.forEach{$0.isHidden=true};enemy.isHidden=false;enemy.position=SCNVector3Zero
  let h=enemy.scale.y
  camera.position=SCNVector3(-0.07,1.55*h,0.86);camera.look(at:SCNVector3(-0.07,1.54*h,0.22))
  SCNTransaction.flush()
  let frame=renderer.snapshot(atTime:0,with:CGSize(width:700,height:700),antialiasingMode:.multisampling4X)
  let data=NSBitmapImageRep(data:frame.tiffRepresentation!)!.representation(using:.png,properties:[:])!
  try data.write(to:URL(fileURLWithPath:output+enemy.identityID+"-face-native.png"))
  print(enemy.identityID,enemy.childNode(withName:"Face.\(enemy.identityID)",recursively:true)?.geometry?.sources.first?.vectorCount ?? 0)
 }
 func saveFrame(_ name:String,_ size:CGSize) throws {
  SCNTransaction.flush()
  let frame=renderer.snapshot(atTime:0,with:size,antialiasingMode:.multisampling4X)
  let data=NSBitmapImageRep(data:frame.tiffRepresentation!)!.representation(using:.png,properties:[:])!
  try data.write(to:URL(fileURLWithPath:output+name))
 }
 enemies.forEach{$0.isHidden=true};enemies[0].isHidden=false
 camera.camera!.fieldOfView=60;camera.position=SCNVector3(0,1.65,1.8);camera.look(at:SCNVector3(0,1.02,0))
 try saveFrame("near-zombie-1.8m-native.png",CGSize(width:800,height:1000))
 for (i,enemy) in enemies.enumerated() {enemy.isHidden=false;enemy.position=SCNVector3(Float(i%4)*1.15-1.72,0,-Float(i/4)*1.8)}
 camera.camera!.fieldOfView=50;camera.position=SCNVector3(0,2.2,6.5);camera.look(at:SCNVector3(0,1.0,-0.8))
 try saveFrame("zombie-variants-native.png",CGSize(width:1400,height:850))

 }
}
