import Foundation
import os

public enum Log {
    private static let subsystem = "local.bargi.faceunlock"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let camera = Logger(subsystem: subsystem, category: "camera")
    public static let vision = Logger(subsystem: subsystem, category: "vision")
    public static let lock = Logger(subsystem: subsystem, category: "lock")
    public static let input = Logger(subsystem: subsystem, category: "input")
}
