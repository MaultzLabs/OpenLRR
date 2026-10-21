import Foundation

@main struct LightWaveSceneTests {
    static func main() throws {
        let scene = """
        LWSC
        1
        FirstFrame 0
        LastFrame 20
        FrameStep 1
        FramesPerSecond 25.0000
        LoadObject Interface\\FrontEnd\\Rock_wipe\\Boulder1.lwo
        ObjectMotion (unnamed)
        9
        2
        0 2 4 0 0 0 1 1 1
        0 0 0 0 0
        10 12 14 90 0 0 2 2 2
        20 1 0 0 0
        EndBehavior 1
        AddNullObject WipeGroup
        ObjectMotion (unnamed)
        9
        1
        1 2 3 0 0 0 1 1 1
        0 0 0 0 0
        ParentObject 1
        """
        let parsed = try LightWaveScene(data: Data(scene.utf8))
        precondition(parsed.firstFrame == 0 && parsed.lastFrame == 20)
        precondition(parsed.frameCount == 21 && parsed.framesPerSecond == 25)
        precondition(abs(parsed.duration - 0.84) < 0.0001)
        precondition(parsed.objects.count == 2)
        precondition(parsed.objects[0].filename?.hasSuffix("Boulder1.lwo") == true)
        precondition(parsed.objects[0].keys.count == 2)
        precondition(parsed.objects[0].channels(at: 0)[0] == 0)
        precondition(parsed.objects[0].channels(at: 10)[0] == 5)
        precondition(parsed.objects[0].channels(at: 10)[6] == 1.5)
        precondition(parsed.objects[0].channels(at: 25)[3] == 90)
        precondition(parsed.objects[1].filename == nil)
        precondition(parsed.objects[1].parentIndex == 1)

        let paths = LightWaveScene.candidatePaths(
            reference: "Rock_wipe\\Boulder1.lwo",
            scenePath: "Interface/FrontEnd/Rock_wipe/RockWipe.lws")
        precondition(paths.contains("Interface/FrontEnd/Rock_wipe/Boulder1.lwo"))
        precondition(LightWaveScene.candidatePaths(
            reference: "C:\\Games\\Boulder2.lwo",
            scenePath: "Interface/FrontEnd/Rock_wipe/RockWipe.lws")
            .contains("Interface/FrontEnd/Rock_wipe/Boulder2.lwo"))
        precondition(LightWaveScene.candidatePaths(
            reference: "../bad.txt", scenePath: "Interface/RockWipe.lws").isEmpty)

        func mustReject(_ name: String, _ content: String) {
            do {
                _ = try LightWaveScene(data: Data(content.utf8))
                preconditionFailure("Accepted invalid LWS: \(name)")
            } catch is LightWaveScene.SceneError {} catch {
                preconditionFailure("Unexpected error: \(error)")
            }
        }
        mustReject("wrong version", "LWSC\n3\nFirstFrame 0\nLastFrame 20")
        mustReject("invalid frame", "LWSC\n1\nFirstFrame 20\nLastFrame 0")
        mustReject("oversized animation", "LWSC\n1\nFirstFrame 0\nLastFrame 100000")
        mustReject("empty ObjectMotion", "LWSC\n1\nFirstFrame 0\nLastFrame 20\nLoadObject Boulder1.lwo\nObjectMotion\n9")
        mustReject("NaN", """
        LWSC
        1
        FirstFrame 0
        LastFrame 20
        LoadObject Boulder1.lwo
        ObjectMotion (unnamed)
        9
        1
        NaN 0 0 0 0 0 1 1 1
        0 0 0 0 0
        """)
        print("PASS: original LWSC1 scene frames, animated 9-channel LWO motion, parent references and safety")
    }
}
