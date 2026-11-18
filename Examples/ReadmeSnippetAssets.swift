import Foundation
import Kadr

// The names the README snippets use, standing in for an app's own state. The
// files do not need to exist: the snippets are compiled, never run.
//
// `video` is computed rather than stored, so the snippets that shadow it with a
// local of the same name read as they do in the README.

var video: Video {
    Video { VideoClip(url: URL(fileURLWithPath: "/tmp/kadr-readme/hero.mov")) }
}

let projectURL = URL(fileURLWithPath: "/tmp/kadr-readme/project.kadr")
let mediaDirectory = URL(fileURLWithPath: "/tmp/kadr-readme/media", isDirectory: true)

/// The app's own save, called once the user has seen what would be lost.
func save() throws {}

/// The app's own way of putting sentences in front of the user.
func show(_ messages: [String]) {}
