//  Log.swift
//  Lightweight wrapper around os.Logger. View output in Console.app
//  (subsystem: com.ufoym.winmove).

import os

enum Log {
    private static let logger = Logger(subsystem: "com.ufoym.winmove", category: "default")

    static func write(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
