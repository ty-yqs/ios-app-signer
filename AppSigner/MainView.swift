//
//  ViewController.swift
//  AppSigner
//
//  Created by Daniel Radtke on 11/2/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Cocoa
import Foundation

class MainView: NSView, URLSessionDataDelegate, URLSessionDelegate, URLSessionDownloadDelegate {
    
    //MARK: IBOutlets
    @IBOutlet var ProvisioningProfilesPopup: NSPopUpButton!
    @IBOutlet var CodesigningCertsPopup: NSPopUpButton!
    @IBOutlet var StatusLabel: NSTextField!
    @IBOutlet var InputFileText: NSTextField!
    @IBOutlet var BrowseButton: NSButton!
    @IBOutlet var StartButton: NSButton!
    @IBOutlet var NewApplicationIDTextField: NSTextField!
    @IBOutlet var downloadProgress: NSProgressIndicator!
    @IBOutlet var appDisplayName: NSTextField!
    @IBOutlet var appShortVersion: NSTextField!
    @IBOutlet var appVersion: NSTextField!
    @IBOutlet var ignorePluginsCheckbox: NSButton!
    @IBOutlet var noGetTaskAllowCheckbox: NSButton!
    @IBOutlet var InputAppIconText: NSTextField!
    @IBOutlet var BrowseAppIconButton: NSButton!

    
    //MARK: Variables
    var provisioningProfiles:[ProvisioningProfile] = []
    @objc var codesigningCerts: [String] = []
    @objc var profileFilename: String?
    @objc var ReEnableNewApplicationID = false
    @objc var PreviousNewApplicationID = ""
    @objc var outputFile: String?
    var startSize: CGFloat?
    @objc var NibLoaded = false
    var shouldCheckPlugins: Bool!
    var shouldSkipGetTaskAllow: Bool!

    //MARK: Constants
    let signableExtensions = ["dylib","so","0","vis","pvr","framework","appex","app"]
    @objc let defaults = UserDefaults()
    @objc let fileManager = FileManager.default
    @objc let bundleID = Bundle.main.bundleIdentifier
    @objc let arPath = "/usr/bin/ar"
    @objc let mktempPath = "/usr/bin/mktemp"
    @objc let tarPath = "/usr/bin/tar"
    @objc let unzipPath = "/usr/bin/unzip"
    @objc let zipPath = "/usr/bin/zip"
    @objc let defaultsPath = "/usr/bin/defaults"
    @objc let codesignPath = "/usr/bin/codesign"
    @objc let securityPath = "/usr/bin/security"
    @objc let chmodPath = "/bin/chmod"
//    let plistbuddyPath = "/usr/libexec/plistbuddy"
    
    //MARK: Drag / Drop
    static let urlFileTypes = ["ipa", "deb"]
    static let allowedFileTypes = urlFileTypes + ["app", "appex", "xcarchive"]
    static let fileTypes = allowedFileTypes + ["mobileprovision"]
    @objc var fileTypeIsOk = false

    static let allowedImageTypes = ["png"]

    @objc func fileDropped(_ filename: String){
        switch filename.pathExtension.lowercased() {
        case let ext where MainView.allowedFileTypes.contains(ext):
            InputFileText.stringValue = filename
        case "mobileprovision":
            ProvisioningProfilesPopup.selectItem(at: 1)
            checkProfileID(ProvisioningProfile(filename: filename))
        default:
            break
        }
    }
    
    @objc func urlDropped(_ url: NSURL){
        if let urlString = url.absoluteString {
            InputFileText.stringValue = urlString
        }
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if checkExtension(sender) == true {
            self.fileTypeIsOk = true
            return .copy
        } else {
            self.fileTypeIsOk = false
            return NSDragOperation()
        }
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if self.fileTypeIsOk {
            return .copy
        } else {
            return NSDragOperation()
        }
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let board = pasteboard.propertyList(forType: NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")) as? NSArray {
            if let filePath = board[0] as? String {
                
                fileDropped(filePath)
                return true
            }
        }
        if let types = pasteboard.types {
            if types.contains(NSPasteboard.PasteboardType(rawValue: "NSURLPboardType")) {
                if let url = NSURL(from: pasteboard) {
                    urlDropped(url)
                }
            }
        }
        return false
    }
    
    @objc func checkExtension(_ drag: NSDraggingInfo) -> Bool {
        if let board = drag.draggingPasteboard.propertyList(forType: NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")) as? NSArray,
            let path = board[0] as? String {
                return MainView.fileTypes.contains(path.pathExtension.lowercased())
        }
        if let types = drag.draggingPasteboard.types {
            if types.contains(NSPasteboard.PasteboardType(rawValue: "NSURLPboardType")) {
                if let url = NSURL(from: drag.draggingPasteboard),
                    let suffix = url.pathExtension {
                        return MainView.urlFileTypes.contains(suffix.lowercased())
                }
            }
        }
        return false
    }
    
    //MARK: Functions
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType"), NSPasteboard.PasteboardType(rawValue: "NSURLPboardType")])
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType"), NSPasteboard.PasteboardType(rawValue: "NSURLPboardType")])
    }
    override func awakeFromNib() {
        super.awakeFromNib()
        
        if NibLoaded == false {
            NibLoaded = true
            
            // Do any additional setup after loading the view.
            populateProvisioningProfiles()
            populateCodesigningCerts()
            if let defaultCert = defaults.string(forKey: "signingCertificate") {
                if codesigningCerts.contains(defaultCert) {
                    Log.write("从默认证书加载: \(defaultCert)")
                    CodesigningCertsPopup.selectItem(withTitle: defaultCert)
                }
            }
            setStatus("已准备好")
            if checkXcodeCLI() == false {
                if #available(OSX 10.10, *) {
                    let _ = installXcodeCLI()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "请安装Xcode命令行工具并重新启动此应用程序"
                    alert.runModal()
                }
                
                NSApplication.shared.terminate(self)
            }
            UpdatesController.checkForUpdate()
        }
    }
    
    func installXcodeCLI() -> AppSignerTaskOutput {
        return Process().execute("/usr/bin/xcode-select", workingDirectory: nil, arguments: ["--install"])
    }
    
    @objc func checkXcodeCLI() -> Bool {
        if #available(OSX 10.10, *) {
            if Process().execute("/usr/bin/xcode-select", workingDirectory: nil, arguments: ["-p"]).status   != 0 {
                return false
            }
        } else {
            if Process().execute("/usr/sbin/pkgutil", workingDirectory: nil, arguments: ["--pkg-info=com.apple.pkg.DeveloperToolsCLI"]).status != 0 {
                // Command line tools not available
                return false
            }
        }
        
        return true
    }
    
    @objc func makeTempFolder()->String?{
        let tempTask = Process().execute(mktempPath, workingDirectory: nil, arguments: ["-d","-t",bundleID!])
        if tempTask.status != 0 {
            return nil
        }
        return tempTask.output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    @objc func setStatus(_ status: String){
        if (!Thread.isMainThread){
            DispatchQueue.main.sync{
                setStatus(status)
            }
        }
        else{
            StatusLabel.stringValue = status
            Log.write(status)
        }
    }
    
    @objc func populateProvisioningProfiles(){
        let zeroWidthSpace = "​"
        self.provisioningProfiles = ProvisioningProfile.getProfiles().sorted {
            ($0.name == $1.name && $0.created.timeIntervalSince1970 > $1.created.timeIntervalSince1970) || $0.name < $1.name
        }
        setStatus("已发现 \(provisioningProfiles.count) 个描述文件 \(provisioningProfiles.count>1 || provisioningProfiles.count<1 ? "s":"")")
        ProvisioningProfilesPopup.removeAllItems()
        ProvisioningProfilesPopup.addItems(withTitles: [
            "只重签名",
            "选择文件",
            "––––––––––––––––––––––"
        ])
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        var newProfiles: [ProvisioningProfile] = []
        var zeroWidthPadding: String = ""
        for profile in provisioningProfiles {
            zeroWidthPadding = "\(zeroWidthPadding)\(zeroWidthSpace)"
            if profile.expires.timeIntervalSince1970 > Date().timeIntervalSince1970 {
                newProfiles.append(profile)
                
                ProvisioningProfilesPopup.addItem(withTitle: "\(profile.name)\(zeroWidthPadding) (\(profile.teamID))")
                
                let toolTipItems = [
                    "\(profile.name)",
                    "",
                    "Team ID: \(profile.teamID)",
                    "Created: \(formatter.string(from: profile.created as Date))",
                    "Expires: \(formatter.string(from: profile.expires as Date))"
                ]
                ProvisioningProfilesPopup.lastItem!.toolTip = toolTipItems.joined(separator: "\n")
                setStatus("添加描述文件 \(profile.appID), 将在 (\(formatter.string(from: profile.expires as Date))) 过期")
            } else {
                setStatus("跳过描述文件 \(profile.appID), 已在 (\(formatter.string(from: profile.expires as Date))) 过期")
            }
        }
        self.provisioningProfiles = newProfiles
        chooseProvisioningProfile(ProvisioningProfilesPopup)
    }
    
    @objc func getCodesigningCerts() -> [String] {
        var output: [String] = []
        let securityResult = Process().execute(securityPath, workingDirectory: nil, arguments: ["find-identity","-v","-p","appleID"])
        if securityResult.output.count < 1 {
            return output
        }
        let rawResult = securityResult.output.components(separatedBy: "\"")
        
        var index: Int
        
        for index in stride(from: 0, through: rawResult.count - 2, by: 2) {
            if !(rawResult.count - 1 < index + 1) {
                output.append(rawResult[index+1])
            }
        }
        return output.sorted()
    }
    
    @objc func showCodesignCertsErrorAlert(){
        let alert = NSAlert()
        alert.messageText = "没有已发现的签名证书"
        alert.informativeText = "我应该可以尝试自动修复此问题，想让我试试吗？"
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            if let tempFolder = makeTempFolder() {
                iASShared.fixSigning(tempFolder)
                try? fileManager.removeItem(atPath: tempFolder)
                populateCodesigningCerts()
            }
        }
    }
    
    @objc func populateCodesigningCerts() {
        CodesigningCertsPopup.removeAllItems()
        self.codesigningCerts = getCodesigningCerts()
        
        setStatus("已找到 \(self.codesigningCerts.count) 个签名证书 \(self.codesigningCerts.count>1 || self.codesigningCerts.count<1 ? "s":"")")
        if self.codesigningCerts.count > 0 {
            for cert in self.codesigningCerts {
                CodesigningCertsPopup.addItem(withTitle: cert)
                setStatus("已添加签名证书 \"\(cert)\"")
            }
        } else {
            showCodesignCertsErrorAlert()
        }
        
    }
    
    func checkProfileID(_ profile: ProvisioningProfile?){
        if let profile = profile {
            self.profileFilename = profile.filename
            setStatus("已选择描述文件 \(profile.appID)")
            if profile.expires.timeIntervalSince1970 < Date().timeIntervalSince1970 {
                ProvisioningProfilesPopup.selectItem(at: 0)
                setStatus("描述文件已过期")
                chooseProvisioningProfile(ProvisioningProfilesPopup)
            }
            if profile.appID.firstIndex(of: "*") == nil {
                // Not a wildcard profile
                NewApplicationIDTextField.stringValue = profile.appID
                NewApplicationIDTextField.isEnabled = false
            } else {
                // Wildcard profile
                if NewApplicationIDTextField.isEnabled == false {
                    NewApplicationIDTextField.stringValue = ""
                    NewApplicationIDTextField.isEnabled = true
                }
            }
        } else {
            ProvisioningProfilesPopup.selectItem(at: 0)
            setStatus("无效的描述文件")
            chooseProvisioningProfile(ProvisioningProfilesPopup)
        }
    }
    
    @objc func controlsEnabled(_ enabled: Bool){
        
        if (!Thread.isMainThread){
            DispatchQueue.main.sync{
                controlsEnabled(enabled)
            }
        }
        else{
            if(enabled){
                InputFileText.isEnabled = true
                BrowseButton.isEnabled = true
                ProvisioningProfilesPopup.isEnabled = true
                CodesigningCertsPopup.isEnabled = true
                NewApplicationIDTextField.isEnabled = ReEnableNewApplicationID
                NewApplicationIDTextField.stringValue = PreviousNewApplicationID
                StartButton.isEnabled = true
                appDisplayName.isEnabled = true
            } else {
                // Backup previous values
                PreviousNewApplicationID = NewApplicationIDTextField.stringValue
                ReEnableNewApplicationID = NewApplicationIDTextField.isEnabled
                
                InputFileText.isEnabled = false
                BrowseButton.isEnabled = false
                ProvisioningProfilesPopup.isEnabled = false
                CodesigningCertsPopup.isEnabled = false
                NewApplicationIDTextField.isEnabled = false
                StartButton.isEnabled = false
                appDisplayName.isEnabled = false
            }
        }
    }
    
    @objc func recursiveDirectorySearch(_ path: String, extensions: [String], found: ((_ file: String) -> Void)){
        
        if let files = try? fileManager.contentsOfDirectory(atPath: path) {
            var isDirectory: ObjCBool = true
            
            for file in files {
                let currentFile = path.stringByAppendingPathComponent(file)
                fileManager.fileExists(atPath: currentFile, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    recursiveDirectorySearch(currentFile, extensions: extensions, found: found)
                }
                if extensions.contains(file.pathExtension) {
                    if file.pathExtension != "" || file == "IpaSecurityRestriction" {
                        found(currentFile)
                    } else {
                        //NSLog("couldnt find: %@", file)
                    }
                } else if isDirectory.boolValue == false && checkMachOFile(currentFile) {
                    found(currentFile)
                }
                
            }
        }
    }

    func allowRecursiveSearchAt(_ path: String) -> Bool {
        return shouldCheckPlugins || path.lastPathComponent != "PlugIns"
    }
    
    /// check if Mach-O file
    @objc func checkMachOFile(_ path: String) -> Bool {
        if let file = FileHandle(forReadingAtPath: path) {
            let data = file.readData(ofLength: 4)
            file.closeFile()
            var machOFile = data.elementsEqual([0xCE, 0xFA, 0xED, 0xFE]) || data.elementsEqual([0xCF, 0xFA, 0xED, 0xFE]) || data.elementsEqual([0xCA, 0xFE, 0xBA, 0xBE])
            
            if machOFile == false && signableExtensions.contains(path.lastPathComponent.pathExtension.lowercased()) {
                Log.write("通过扩展检测到二进制文件: \(path)")
                machOFile = true
            }
            return machOFile
        }
        return false
    }
    
    func unzip(_ inputFile: String, outputPath: String)->AppSignerTaskOutput {
        return Process().execute(unzipPath, workingDirectory: nil, arguments: ["-q",inputFile,"-d",outputPath])
    }
    func zip(_ inputPath: String, outputFile: String)->AppSignerTaskOutput {
        return Process().execute(zipPath, workingDirectory: inputPath, arguments: ["-qry", outputFile, "."])
    }
    
    @objc func cleanup(_ tempFolder: String){
        do {
            Log.write("删除: \(tempFolder)")
            try fileManager.removeItem(atPath: tempFolder)
        } catch let error as NSError {
            setStatus("无法删除临时文件夹")
            Log.write(error.localizedDescription)
        }
        controlsEnabled(true)
    }
    @objc func bytesToSmallestSi(_ size: Double) -> String {
        let prefixes = ["","K","M","G","T","P","E","Z","Y"]
        for i in 1...6 {
            let nextUnit = pow(1024.00, Double(i+1))
            let unitMax = pow(1024.00, Double(i))
            if size < nextUnit {
                return "\(round((size / unitMax)*100)/100)\(prefixes[i])B"
            }
            
        }
        return "\(size)B"
    }
    @objc func getPlistKey(_ plist: String, keyName: String)->String? {
        let dictionary = NSDictionary(contentsOfFile: plist);
        return dictionary?[keyName] as? String
    }
    
    func setPlistKey(_ plist: String, keyName: String, value: String)->AppSignerTaskOutput {
        return Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write", plist, keyName, value])
    }

    @objc func getPlistDictionaryKey(_ plist: String, keyName: String)->[String:AnyObject]? {
        let dictionary = NSDictionary(contentsOfFile: plist)
        return dictionary?[keyName] as? Dictionary
    }

    //MARK: NSURL Delegate
    @objc var downloading = false
    @objc var downloadError: NSError?
    @objc var downloadPath: String!
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        downloadError = downloadTask.error as NSError?
        if downloadError == nil {
            do {
                try fileManager.moveItem(at: location, to: URL(fileURLWithPath: downloadPath))
            } catch let error as NSError {
                setStatus("无法移动下载的文件")
                Log.write(error.localizedDescription)
            }
        }
        downloading = false
        downloadProgress.doubleValue = 0.0
        downloadProgress.stopAnimation(nil)
        DispatchQueue.main.async {
            self.downloadProgress.isHidden = true
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
        //StatusLabel.stringValue = "Downloading file: \(bytesToSmallestSi(Double(totalBytesWritten))) / \(bytesToSmallestSi(Double(totalBytesExpectedToWrite)))"
        let percentDownloaded = (Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) * 100
        downloadProgress.doubleValue = percentDownloaded
    }
    
    //MARK: Codesigning
    @discardableResult
    func codeSign(_ file: String, certificate: String, entitlements: String?,before:((_ file: String, _ certificate: String, _ entitlements: String?)->Void)?, after: ((_ file: String, _ certificate: String, _ entitlements: String?, _ codesignTask: AppSignerTaskOutput)->Void)?)->AppSignerTaskOutput{

        var needEntitlements: Bool = false
        let filePath: String
        switch file.pathExtension.lowercased() {
        case "framework":
            // append executable file in framework
            let fileName = file.lastPathComponent.stringByDeletingPathExtension
            filePath = file.stringByAppendingPathComponent(fileName)
        case "app", "appex":
            // read executable file from Info.plist
            let infoPlist = file.stringByAppendingPathComponent("Info.plist")
            let executableFile = getPlistKey(infoPlist, keyName: "CFBundleExecutable")!
            filePath = file.stringByAppendingPathComponent(executableFile)

            if let entitlementsPath = entitlements, fileManager.fileExists(atPath: entitlementsPath) {
                needEntitlements = true
            }
        default:
            filePath = file
        }

        if let beforeFunc = before {
            beforeFunc(file, certificate, entitlements)
        }

        var arguments = ["-f", "-s", certificate]
        if needEntitlements {
            arguments += ["--entitlements", entitlements!]
        }
        arguments.append(filePath)

        let codesignTask = Process().execute(codesignPath, workingDirectory: nil, arguments: arguments)
        if codesignTask.status != 0 {
            Log.write("代码签名失败: \(codesignTask.output)")
        }
        
        if let afterFunc = after {
            afterFunc(file, certificate, entitlements, codesignTask)
        }
        return codesignTask
    }
    func testSigning(_ certificate: String, tempFolder: String )->Bool? {
        let codesignTempFile = tempFolder.stringByAppendingPathComponent("test-sign")
        
        // Copy our binary to the temp folder to use for testing.
        let path = ProcessInfo.processInfo.arguments[0]
        if (try? fileManager.copyItem(atPath: path, toPath: codesignTempFile)) != nil {
            codeSign(codesignTempFile, certificate: certificate, entitlements: nil, before: nil, after: nil)
            
            let verificationTask = Process().execute(codesignPath, workingDirectory: nil, arguments: ["-v",codesignTempFile])
            try? fileManager.removeItem(atPath: codesignTempFile)
            if verificationTask.status == 0 {
                Log.write("Error testing codesign: \(verificationTask.output)")
                return true
            } else {
                return false
            }
        } else {
            setStatus("测试代码签名失败")
        }
        return nil
    }
    
    @objc func startSigning() {
        let inputFile = InputFileText.stringValue
        if inputFile.pathExtension.lowercased() == "appex" {
            outputFile = inputFile
        } else {
            //MARK: Get output filename
            let saveDialog = NSSavePanel()
            saveDialog.allowedFileTypes = ["ipa"]
            saveDialog.nameFieldStringValue = inputFile.lastPathComponent.stringByDeletingPathExtension
            if saveDialog.runModal().rawValue == NSFileHandlingPanelOKButton {
                outputFile = saveDialog.url!.path
            } else {
                outputFile = nil
            }
        }
        if outputFile != nil {
            controlsEnabled(false)
            Thread.detachNewThreadSelector(#selector(self.signingThread), toTarget: self, with: nil)
        }
    }
    
    @objc func signingThread(){
        
        
        //MARK: Set up variables
        var warnings = 0
        var inputFile : String = ""
        var signingCertificate : String?
        var newApplicationID : String = ""
        var newDisplayName : String = ""
        var newShortVersion : String = ""
        var newVersion : String = ""
        var newAppIcon : String = ""

        DispatchQueue.main.sync {
            downloadProgress.isHidden = true
            inputFile = self.InputFileText.stringValue
            signingCertificate = self.CodesigningCertsPopup.selectedItem?.title
            newApplicationID = self.NewApplicationIDTextField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            newDisplayName = self.appDisplayName.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            newShortVersion = self.appShortVersion.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            newVersion = self.appVersion.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            newAppIcon = self.InputAppIconText.stringValue
            shouldCheckPlugins = ignorePluginsCheckbox.state == .off
            shouldSkipGetTaskAllow = noGetTaskAllowCheckbox.state == .on
        }

        var provisioningFile = self.profileFilename
        let inputStartsWithHTTP = inputFile.lowercased().substring(to: inputFile.index(inputFile.startIndex, offsetBy: 4)) == "http"
        var eggCount: Int = 0
        var continueSigning: Bool? = nil
        
        //MARK: Sanity checks
        
        // Check signing certificate selection
        if signingCertificate == nil {
            setStatus("没有选择签名证书")
            return
        }
        
        // Check if input file exists
        var inputIsDirectory: ObjCBool = false
        if !inputStartsWithHTTP && !fileManager.fileExists(atPath: inputFile, isDirectory: &inputIsDirectory){
            DispatchQueue.main.async(execute: {
                let alert = NSAlert()
                alert.messageText = "输入文件未找到"
                alert.addButton(withTitle: "OK")
                alert.informativeText = "文件 \(inputFile) 不能被找到"
                alert.runModal()
                self.controlsEnabled(true)
            })
            return
        }
        
        //MARK: Create working temp folder
        var tempFolder: String! = nil
        if let tmpFolder = makeTempFolder() {
            tempFolder = tmpFolder
        } else {
            setStatus("创建临时文件夹时出错")
            return
        }
        let workingDirectory = tempFolder.stringByAppendingPathComponent("out")
        let eggDirectory = tempFolder.stringByAppendingPathComponent("eggs")
        let payloadDirectory = workingDirectory.stringByAppendingPathComponent("Payload/")
        let entitlementsPlist = tempFolder.stringByAppendingPathComponent("entitlements.plist")
        
        Log.write("临时文件夹: \(tempFolder)")
        Log.write("工作文件夹: \(workingDirectory)")
        Log.write("载荷文件夹: \(payloadDirectory)")
        
        //MARK: Codesign Test
        
        DispatchQueue.main.async(execute: {
            if let codesignResult = self.testSigning(signingCertificate!, tempFolder: tempFolder) {
                if codesignResult == false {
                    let alert = NSAlert()
                    alert.messageText = "代码签名失败"
                    alert.addButton(withTitle: "Yes")
                    alert.addButton(withTitle: "No")
                    alert.informativeText = "您的代码签名证书似乎有错误，是否希望我尝试解决此问题？"
                    let response = alert.runModal()
                    if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                        iASShared.fixSigning(tempFolder)
                        if self.testSigning(signingCertificate!, tempFolder: tempFolder) == false {
                            let errorAlert = NSAlert()
                            errorAlert.messageText = "Unable to Fix"
                            errorAlert.addButton(withTitle: "OK")
                            errorAlert.informativeText = "我无法自动解决您的代码签名问题☹\n\n如果您以前使用钥匙串信任您的证书，请将信任设置调回系统默认值。"
                            errorAlert.runModal()
                            continueSigning = false
                            return
                        }
                    } else {
                        continueSigning = false
                        return
                    }
                }
            }
            continueSigning = true
        })
        
        
        while true {
            if continueSigning != nil {
                if continueSigning! == false {
                    continueSigning = nil
                    cleanup(tempFolder); return
                }
                break
            }
            usleep(100)
        }
        
        //MARK: Create Egg Temp Directory
        do {
            try fileManager.createDirectory(atPath: eggDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            setStatus("创建临时目录时出错")
            Log.write(error.localizedDescription)
            cleanup(tempFolder); return
        }
        
        //MARK: Download file
        downloading = false
        downloadError = nil
        downloadPath = tempFolder.stringByAppendingPathComponent("download.\(inputFile.pathExtension)")
        
        if inputStartsWithHTTP {
            let defaultConfigObject = URLSessionConfiguration.default
            let defaultSession = Foundation.URLSession(configuration: defaultConfigObject, delegate: self, delegateQueue: OperationQueue.main)
            if let url = URL(string: inputFile) {
                downloading = true
                
                let downloadTask = defaultSession.downloadTask(with: url)
                setStatus("下载文件")
                DispatchQueue.main.async {
                    self.downloadProgress.isHidden = false
                }
                downloadProgress.startAnimation(nil)
                downloadTask.resume()
                defaultSession.finishTasksAndInvalidate()
            }
            
            while downloading {
                usleep(100000)
            }
            if downloadError != nil {
                setStatus("下载文件失败, \(downloadError!.localizedDescription.lowercased())")
                cleanup(tempFolder); return
            } else {
                inputFile = downloadPath
            }
        }
        
        //MARK: Process input file
        switch(inputFile.pathExtension.lowercased()){
        case "deb":
            //MARK: --Unpack deb
            let debPath = tempFolder.stringByAppendingPathComponent("deb")
            do {
                
                try fileManager.createDirectory(atPath: debPath, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("提取deb文件")
                let debTask = Process().execute(arPath, workingDirectory: debPath, arguments: ["-x", inputFile])
                Log.write(debTask.output)
                if debTask.status != 0 {
                    setStatus("处理deb文件时出错")
                    cleanup(tempFolder); return
                }
                
                var tarUnpacked = false
                for tarFormat in ["tar","tar.gz","tar.bz2","tar.lzma","tar.xz"]{
                    let dataPath = debPath.stringByAppendingPathComponent("data.\(tarFormat)")
                    if fileManager.fileExists(atPath: dataPath){
                        
                        setStatus("解包数据.\(tarFormat)")
                        let tarTask = Process().execute(tarPath, workingDirectory: debPath, arguments: ["-xf",dataPath])
                        Log.write(tarTask.output)
                        if tarTask.status == 0 {
                            tarUnpacked = true
                        }
                        break
                    }
                }
                if !tarUnpacked {
                    setStatus("解包 data.tar 时出错")
                    cleanup(tempFolder); return
                }
              
              var sourcePath = debPath.stringByAppendingPathComponent("Applications")
              if fileManager.fileExists(atPath: debPath.stringByAppendingPathComponent("var/mobile/Applications")){
                  sourcePath = debPath.stringByAppendingPathComponent("var/mobile/Applications")
              }
              
              try fileManager.moveItem(atPath: sourcePath, toPath: payloadDirectory)
                
            } catch {
                setStatus("处理deb文件时出错")
                cleanup(tempFolder); return
            }
            
        case "ipa":
            //MARK: --Unzip ipa
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("提取ipa文件")
                
                let unzipTask = self.unzip(inputFile, outputPath: workingDirectory)
                if unzipTask.status != 0 {
                    setStatus("提取ipa文件时出错")
                    cleanup(tempFolder); return
                }
            } catch {
                setStatus("提取ipa文件时出错")
                cleanup(tempFolder); return
            }
            
        case "app", "appex":
            //MARK: --Copy app bundle
            if !inputIsDirectory.boolValue {
                setStatus("不支持的输入文件")
                cleanup(tempFolder); return
            }
            do {
                try fileManager.createDirectory(atPath: payloadDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("正在将应用程序复制到有效负载目录")
                try fileManager.copyItem(atPath: inputFile, toPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent))
            } catch {
                setStatus("将应用程序复制到有效负载目录时出错")
                cleanup(tempFolder); return
            }
            
        case "xcarchive":
            //MARK: --Copy app bundle from xcarchive
            if !inputIsDirectory.boolValue {
                setStatus("不支持的输入文件")
                cleanup(tempFolder); return
            }
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("正在将应用程序复制到有效负载目录")
                try fileManager.copyItem(atPath: inputFile.stringByAppendingPathComponent("Products/Applications/"), toPath: payloadDirectory)
            } catch {
                setStatus("将应用程序复制到有效负载目录时出错")
                cleanup(tempFolder); return
            }
            
        default:
            setStatus("不支持的输入文件")
            cleanup(tempFolder); return
        }
        
        if !fileManager.fileExists(atPath: payloadDirectory){
            setStatus("有效负载目录不存在")
            cleanup(tempFolder); return
        }
        
        // Loop through app bundles in payload directory
        do {
            let files = try fileManager.contentsOfDirectory(atPath: payloadDirectory)
            var isDirectory: ObjCBool = true
            
            for file in files {
                
                fileManager.fileExists(atPath: payloadDirectory.stringByAppendingPathComponent(file), isDirectory: &isDirectory)
                if !isDirectory.boolValue { continue }
                
                //MARK: Bundle variables setup
                let appBundlePath = payloadDirectory.stringByAppendingPathComponent(file)
                let appBundleInfoPlist = appBundlePath.stringByAppendingPathComponent("Info.plist")
                let appBundleProvisioningFilePath = appBundlePath.stringByAppendingPathComponent("embedded.mobileprovision")
                let useAppBundleProfile = (provisioningFile == nil && fileManager.fileExists(atPath: appBundleProvisioningFilePath))
                
                //MARK: Delete CFBundleResourceSpecification from Info.plist
                Log.write(Process().execute(defaultsPath, workingDirectory: nil, arguments: ["delete",appBundleInfoPlist,"CFBundleResourceSpecification"]).output)
                
                //MARK: Copy Provisioning Profile
                if provisioningFile != nil {
                    if fileManager.fileExists(atPath: appBundleProvisioningFilePath) {
                        setStatus("删除 embedded.mobileprovision")
                        do {
                            try fileManager.removeItem(atPath: appBundleProvisioningFilePath)
                        } catch let error as NSError {
                            setStatus("删除 embedded.mobileprovision 失败")
                            Log.write(error.localizedDescription)
                            cleanup(tempFolder); return
                        }
                    }
                    setStatus("将描述文件复制到应用程序包")
                    do {
                        try fileManager.copyItem(atPath: provisioningFile!, toPath: appBundleProvisioningFilePath)
                    } catch let error as NSError {
                        setStatus("复制描述文件失败")
                        Log.write(error.localizedDescription)
                        cleanup(tempFolder); return
                    }
                }
                
                let bundleID = getPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier")
                
                //MARK: Generate entitlements.plist
                if provisioningFile != nil || useAppBundleProfile {
                    setStatus("分析权限")
                    
                    if var profile = ProvisioningProfile(filename: useAppBundleProfile ? appBundleProvisioningFilePath : provisioningFile!){
                        if shouldSkipGetTaskAllow {
                            profile.removeGetTaskAllow()
                        }
                        let isWildcard = profile.appID == "*" // TODO: support com.example.* wildcard
                        if !isWildcard && (newApplicationID != "" && newApplicationID != profile.appID) {
                            setStatus("更改appID到 \(newApplicationID) 失败, 描述文件不允许")
                            cleanup(tempFolder); return
                        } else if isWildcard {
                            if newApplicationID != "" {
                                profile.update(trueAppID: newApplicationID)
                            } else if let existingBundleID = bundleID {
                                profile.update(trueAppID: existingBundleID)
                            }
                        }
                        if let entitlements = profile.getEntitlementsPlist() {
                            Log.write("–––––––––––––––––––––––\n\(entitlements)")
                            Log.write("–––––––––––––––––––––––")
                            do {
                                try entitlements.write(toFile: entitlementsPlist, atomically: false, encoding: .utf8)
                                setStatus("保存权限到 \(entitlementsPlist)")
                            } catch let error as NSError {
                                setStatus("写入 entitlements.plist 失败, \(error.localizedDescription)")
                            }
                        } else {
                            setStatus("无法从文件读取权限")
                            warnings += 1
                        }
                    } else {
                        setStatus("无法分析描述文件，它可能已损坏")
                        warnings += 1
                    }
                    
                }
                
                //MARK: Make sure that the executable is well... executable.
                if let bundleExecutable = getPlistKey(appBundleInfoPlist, keyName: "CFBundleExecutable"){
                    _ = Process().execute(chmodPath, workingDirectory: nil, arguments: ["755", appBundlePath.stringByAppendingPathComponent(bundleExecutable)])
                }
                
                //MARK: Change Application ID
                if newApplicationID != "" {
                    
                    if let oldAppID = bundleID {
                        func changeAppexID(_ appexFile: String){
                            guard allowRecursiveSearchAt(appexFile.stringByDeletingLastPathComponent) else {
                                return
                            }

                            let appexPlist = appexFile.stringByAppendingPathComponent("Info.plist")
                            if let appexBundleID = getPlistKey(appexPlist, keyName: "CFBundleIdentifier"){
                                let newAppexID = "\(newApplicationID)\(appexBundleID.substring(from: oldAppID.endIndex))"
                                setStatus("更改 \(appexFile) id 到 \(newAppexID)")
                                _ = setPlistKey(appexPlist, keyName: "CFBundleIdentifier", value: newAppexID)
                            }
                            if Process().execute(defaultsPath, workingDirectory: nil, arguments: ["read", appexPlist,"WKCompanionAppBundleIdentifier"]).status == 0 {
                                _ = setPlistKey(appexPlist, keyName: "WKCompanionAppBundleIdentifier", value: newApplicationID)
                            }
                            // 修复微信改bundleid后安装失败问题
                            let pluginInfoPlist = NSMutableDictionary(contentsOfFile: appexPlist)
                            if let dictionaryArray = pluginInfoPlist?["NSExtension"] as? [String:AnyObject],
                                let attributes : NSMutableDictionary = dictionaryArray["NSExtensionAttributes"] as? NSMutableDictionary,
                                let wkAppBundleIdentifier = attributes["WKAppBundleIdentifier"] as? String{
                                let newAppesID = wkAppBundleIdentifier.replacingOccurrences(of:oldAppID, with:newApplicationID);
                                attributes["WKAppBundleIdentifier"] = newAppesID;
                                pluginInfoPlist!.write(toFile: appexPlist, atomically: true);
                            }
                            recursiveDirectorySearch(appexFile, extensions: ["app"], found: changeAppexID)
                        }
                        recursiveDirectorySearch(appBundlePath, extensions: ["appex"], found: changeAppexID)
                    }
                    
                    setStatus("更改appID 到 \(newApplicationID)")
                    let IDChangeTask = setPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier", value: newApplicationID)
                    if IDChangeTask.status != 0 {
                        setStatus("更改 appID 失败")
                        Log.write(IDChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Display Name
                if newDisplayName != "" {
                    setStatus("更改 app 名称到 \(newDisplayName))")
                    let displayNameChangeTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleDisplayName", newDisplayName])
                    if displayNameChangeTask.status != 0 {
                        setStatus("更改 app 名称失败")
                        Log.write(displayNameChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Version
                if newVersion != "" {
                    setStatus("更改版本失败 \(newVersion)")
                    let versionChangeTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleVersion", newVersion])
                    if versionChangeTask.status != 0 {
                        setStatus("更改版本失败")
                        Log.write(versionChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Short Version
                if newShortVersion != "" {
                    setStatus("更改短版本到 \(newShortVersion)")
                    let shortVersionChangeTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleShortVersionString", newShortVersion])
                    if shortVersionChangeTask.status != 0 {
                        setStatus("更改短版本失败")
                        Log.write(shortVersionChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                func replaceIcons(for key: String, newImage: NSImage) {
                    if let plist = NSMutableDictionary(contentsOfFile: appBundleInfoPlist) {
                        if let iconsDictionary = plist[key] as? [String:AnyObject] {
                            if let primaryIcon = iconsDictionary["CFBundlePrimaryIcon"] as? NSMutableDictionary {
                                primaryIcon["CFBundleIconName"] = "AltIcon"
                                if let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String] {
                                    for iconFile in iconFiles {
                                        let finalIconName = iconFile.hasSuffix("76x76") ? iconFile.appending("@2x~ipad") : iconFile.appending("@2x")
                                        if let iconPath = appBundlePath.stringByAppendingPathComponent(finalIconName).stringByAppendingPathExtension("png") {
                                            if let image = NSImage(contentsOfFile: iconPath) {
                                                if let resizedImage = newImage.resizedImage(newSize: image.size) {
                                                    resizedImage.pngWrite(to: URL(fileURLWithPath: iconPath))
                                                }
                                            }
                                        }
                                    }
                                }
                                plist.write(toFile: appBundleInfoPlist, atomically: true)
                            }
                        }
                    }
                }
                
                //MARK: Change App Icon
                if newAppIcon != "" {
                    if let newImage = NSImage(contentsOfFile: newAppIcon) {
                        replaceIcons(for: "CFBundleIcons", newImage: newImage)
                        replaceIcons(for: "CFBundleIcons~ipad", newImage: newImage)
                    }
                }
                
                func generateFileSignFunc(_ payloadDirectory:String, entitlementsPath: String, signingCertificate: String)->((_ file:String)->Void){
                    
                    
                    let useEntitlements: Bool = ({
                        if fileManager.fileExists(atPath: entitlementsPath) {
                            return true
                        }
                        return false
                    })()
                    
                    func shortName(_ file: String, payloadDirectory: String)->String{
                        return file.substring(from: payloadDirectory.endIndex)
                    }
                    
                    func beforeFunc(_ file: String, certificate: String, entitlements: String?){
                            setStatus("代码签名 \(shortName(file, payloadDirectory: payloadDirectory))\(useEntitlements ? " 使用权限":"")")
                    }
                    
                    func afterFunc(_ file: String, certificate: String, entitlements: String?, codesignOutput: AppSignerTaskOutput){
                        if codesignOutput.status != 0 {
                            setStatus("代码签名失败 \(shortName(file, payloadDirectory: payloadDirectory))")
                            Log.write(codesignOutput.output)
                            warnings += 1
                        }
                    }
                    
                    func output(_ file:String){
                        codeSign(file, certificate: signingCertificate, entitlements: entitlementsPath, before: beforeFunc, after: afterFunc)
                    }
                    return output
                }
                
                //MARK: Codesigning - Eggs
                let eggSigningFunction = generateFileSignFunc(eggDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                func signEgg(_ eggFile: String){
                    eggCount += 1
                    
                    let currentEggPath = eggDirectory.stringByAppendingPathComponent("egg\(eggCount)")
                    let shortName = eggFile.substring(from: payloadDirectory.endIndex)
                    setStatus("提取 \(shortName)")
                    if self.unzip(eggFile, outputPath: currentEggPath).status != 0 {
                        Log.write("Error extracting \(shortName)")
                        return
                    }
                    recursiveDirectorySearch(currentEggPath, extensions: ["egg"], found: signEgg)
                    recursiveDirectorySearch(currentEggPath, extensions: signableExtensions, found: eggSigningFunction)
                    setStatus("压缩 \(shortName)")
                    _ = self.zip(currentEggPath, outputFile: eggFile)                    
                }
                
                recursiveDirectorySearch(appBundlePath, extensions: ["egg"], found: signEgg)
                
                //MARK: Codesigning - App
                let signingFunction = generateFileSignFunc(payloadDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                
                recursiveDirectorySearch(appBundlePath, extensions: signableExtensions, found: signingFunction)
                signingFunction(appBundlePath)
                
                //MARK: Codesigning - Verification
                let verificationTask = Process().execute(codesignPath, workingDirectory: nil, arguments: ["-v",appBundlePath])
                if verificationTask.status != 0 {
                    DispatchQueue.main.async(execute: {
                        let alert = NSAlert()
                        alert.addButton(withTitle: "OK")
                        alert.messageText = "Error verifying code signature!"
                        alert.informativeText = verificationTask.output
                        alert.alertStyle = .critical
                        alert.runModal()
                        self.setStatus("验证代码签名时出错")
                        Log.write(verificationTask.output)
                        self.cleanup(tempFolder); return
                    })
                }
            }
        } catch let error as NSError {
            setStatus("列出有效负载目录中的文件时出错")
            Log.write(error.localizedDescription)
            cleanup(tempFolder); return
        }
        
        //MARK: Packaging
        //Check if output already exists and delete if so
        if fileManager.fileExists(atPath: outputFile!) {
            do {
                try fileManager.removeItem(atPath: outputFile!)
            } catch let error as NSError {
                setStatus("删除输出文件时出错")
                Log.write(error.localizedDescription)
                cleanup(tempFolder)
                return
            }
        }

        switch outputFile?.pathExtension.lowercased() {
        case "ipa":
            setStatus("打包IPA")
            let zipTask = self.zip(workingDirectory, outputFile: outputFile!)
            if zipTask.status != 0 {
                setStatus("打包IPA失败")
            }
        case "appex":
            do {
                try fileManager.copyItem(atPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent), toPath: outputFile!)
            } catch let error as NSError {
                setStatus("拷贝到 \(outputFile!) 失败")
                Log.write(error.localizedDescription)
            }
        default:
            break
        }

        //MARK: Cleanup
        cleanup(tempFolder)
        setStatus("签名完成，文件路径: \(outputFile!)")
    }

    //MARK: IBActions
    @IBAction func chooseProvisioningProfile(_ sender: NSPopUpButton) {
        
        switch(sender.indexOfSelectedItem){
        case 0:
            self.profileFilename = nil
            if NewApplicationIDTextField.isEnabled == false {
                NewApplicationIDTextField.isEnabled = true
                NewApplicationIDTextField.stringValue = ""
            }
            
        case 1:
            let openDialog = NSOpenPanel()
            openDialog.canChooseFiles = true
            openDialog.canChooseDirectories = false
            openDialog.allowsMultipleSelection = false
            openDialog.allowsOtherFileTypes = false
            openDialog.allowedFileTypes = ["mobileprovision"]
            openDialog.runModal()
            if let filename = openDialog.urls.first {
                checkProfileID(ProvisioningProfile(filename: filename.path))
            } else {
                sender.selectItem(at: 0)
                chooseProvisioningProfile(sender)
            }
            
        case 2:
            sender.selectItem(at: 0)
            chooseProvisioningProfile(sender)
            
        default:
            let profile = provisioningProfiles[sender.indexOfSelectedItem - 3]
            checkProfileID(profile)
        }
        
    }
    @IBAction func doBrowse(_ sender: AnyObject) {
        let openDialog = NSOpenPanel()
        openDialog.canChooseFiles = true
        openDialog.canChooseDirectories = false
        openDialog.allowsMultipleSelection = false
        openDialog.allowsOtherFileTypes = false
        openDialog.allowedFileTypes = MainView.allowedFileTypes + MainView.allowedFileTypes.map({ $0.uppercased() })
        openDialog.runModal()
        if let filename = openDialog.urls.first {
            InputFileText.stringValue = filename.path
        }
    }
    @IBAction func chooseSigningCertificate(_ sender: NSPopUpButton) {
        Log.write("将代码签名证书默认设置为: \(sender.stringValue)")
        defaults.setValue(sender.selectedItem?.title, forKey: "signingCertificate")
    }
    
    @IBAction func doSign(_ sender: NSButton) {
        if codesigningCerts.count > 0 {
            NSApplication.shared.windows[0].makeFirstResponder(self)
            startSigning()
        } else {
            showCodesignCertsErrorAlert()
        }
    }
    
    @IBAction func statusLabelClick(_ sender: NSButton) {
        if let outputFile = self.outputFile {
            if fileManager.fileExists(atPath: outputFile) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputFile)])
            }
        }
    }
    @IBAction func doAppIconBrowse(_ sender: AnyObject) {
        let openDialog = NSOpenPanel()
        openDialog.canChooseFiles = true
        openDialog.canChooseDirectories = false
        openDialog.allowsMultipleSelection = false
        openDialog.allowsOtherFileTypes = false
        openDialog.allowedFileTypes = MainView.allowedImageTypes + MainView.allowedImageTypes.map({ $0.uppercased() })
        openDialog.runModal()
        if let filename = openDialog.urls.first {
            InputAppIconText.stringValue = filename.path
        }
    }

}

extension NSImage {

    var pngData: Data? {
        guard let tiffRepresentation = tiffRepresentation, let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .png, properties: [:])
    }
    @discardableResult func pngWrite(to url: URL, options: Data.WritingOptions = .atomic) -> Bool {
        do {
            try pngData?.write(to: url, options: options)
            return true
        } catch {
            print(error)
            return false
        }
    }

    func resizedImage(newSize: NSSize) -> NSImage? {
        let sourceImage = self
        
        if !sourceImage.isValid {
            return nil
        } else {
            let resizedImage = NSImage(size: newSize)
            resizedImage.lockFocus()
            sourceImage.size = newSize
            NSGraphicsContext.current?.imageInterpolation = .high
            sourceImage.draw(at: .zero, from: CGRect(origin: .zero, size: newSize), operation: .copy, fraction: 1.0)
            resizedImage.unlockFocus()
            
            return resizedImage
        }
    }

}
