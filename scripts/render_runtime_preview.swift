// Invoked by render_runtime_preview.py; renders the actual PreviewAnimator through SceneKit.
import Foundation
import SceneKit
import AppKit
import Metal

@main struct RenderNewTrio {
    @MainActor static func main() throws {
        let scene = SCNScene()
        var animators: [PreviewAnimator] = []
        for (index, friend) in [RealmFriend.pufflo, .trufflet, .dottli].enumerated() {
            let imported = try SCNScene(url: URL(fileURLWithPath: "PocketRealm/Resources/Creatures/\(friend.name).usdz"))
            let root = SCNNode()
            for node in imported.rootNode.childNodes { root.addChildNode(node) }
            let slot = SCNNode(); slot.simdPosition.x = Float(index-1) * 0.64
            slot.addChildNode(root); scene.rootNode.addChildNode(slot)
            animators.append(PreviewAnimator(root: root, friend: friend))
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera!.usesOrthographicProjection = true
        camera.camera!.orthographicScale = 0.46
        camera.camera!.zNear = 0.01; camera.camera!.zFar = 10
        camera.position = SCNVector3(0.18,0.62,3.2)
        camera.look(at: SCNVector3(0,0.27,0)); scene.rootNode.addChildNode(camera)
        let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional; key.light!.intensity = 850
        key.position = SCNVector3(-1,2,2); key.look(at: SCNVector3(0,0.2,0)); scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient; fill.light!.intensity = 500
        scene.rootNode.addChildNode(fill)
        scene.background.contents = NSColor(red:0.95,green:0.94,blue:0.89,alpha:1)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        let pipe = Pipe(); let encoder = Process()
        encoder.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        encoder.arguments = ["-y","-loglevel","error","-f","image2pipe","-vcodec","png","-r","12","-i","-","-c:v","libx264","-threads","2","-pix_fmt","yuv420p","-crf","20","-movflags","+faststart","build/new-trio-runtime.partial.mp4"]
        encoder.standardInput = pipe; try encoder.run()
        let cues: [Int: FriendReaction] = [18:.greeting,48:.pet,74:.play,116:.celebrate]
        for frame in 0..<168 {
            try autoreleasepool {
                for animator in animators {
                    if let reaction = cues[frame] { animator.react(reaction) }
                    animator.update(delta: 1.0/12, reducedMotion: false)
                }
                let image = renderer.snapshot(atTime:Double(frame)/12,with:CGSize(width:960,height:420),antialiasingMode:.multisampling4X)
                let data = NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
                try pipe.fileHandleForWriting.write(contentsOf:data)
                if [30,60,94,135].contains(frame) {
                    try data.write(to:URL(fileURLWithPath:"build/new-trio-runtime-\(frame).png"))
                }
            }
            if frame.isMultiple(of:24) { print("RUNTIME_FRAME \(frame)/168") }
        }
        try pipe.fileHandleForWriting.close(); encoder.waitUntilExit()
        precondition(encoder.terminationStatus == 0)
        let output = URL(fileURLWithPath:"Art/Creatures/friends-new-runtime.mp4")
        if FileManager.default.fileExists(atPath:output.path) { try FileManager.default.removeItem(at:output) }
        try FileManager.default.moveItem(at:URL(fileURLWithPath:"build/new-trio-runtime.partial.mp4"),to:output)
        print("NEW_TRIO_RUNTIME_PREVIEW_COMPLETE")
    }
}
