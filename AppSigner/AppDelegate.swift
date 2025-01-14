//
//  AppDelegate.swift
//  AppSigner
//
//  Created by Daniel Radtke on 11/2/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var mainView: MainView!
    @objc let fileManager = FileManager.default
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        try? fileManager.removeItem(atPath: Log.logName)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    @IBAction func fixSigning(_ sender: NSMenuItem) {
        if let tempFolder = mainView.makeTempFolder() {
            iASShared.fixSigning(tempFolder)
            try? fileManager.removeItem(atPath: tempFolder)
            mainView.populateCodesigningCerts()
        }
    }

    @IBAction func nsMenuLinkClick(_ sender: NSMenuLink) {
        NSWorkspace.shared.open(URL(string: sender.url!)!)
    }
    @IBAction func viewLog(_ sender: AnyObject) {
        NSWorkspace.shared.openFile(Log.logName)
    }
    @IBAction func checkForUpdates(_ sender: NSMenuItem) {
        UpdatesController.checkForUpdate(forceShow: true)
        func updateCheckStatus(_ status: Bool, data: Data?, response: URLResponse?, error: Error?){
            if status == false {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    
                    
                    if error != nil {
                        alert.messageText = "检查新版本时出现问题"
                        alert.informativeText = "更多信息可在应用日志中找到"
                        Log.write(error!.localizedDescription)
                    } else {
                        alert.messageText = "您当前正在运行最新版本"
                    }
                    alert.runModal()
                }
            }
        }
        UpdatesController.checkForUpdate(forceShow: true, callbackFunc: updateCheckStatus)
    }
}

