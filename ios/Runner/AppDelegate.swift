import Flutter
import UIKit
import Photos
import Contacts
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
    private let queue = DispatchQueue(label: "clearsafe.read")
    private var handles: [String: (FileHandle, URL?)] = [:]
    private var sizes: [String: Int64] = [:]
    private var omittedComposite = 0
    private var omittedUnreadable = 0
    private var documents: [String: URL] = [:]
    private var pickerResult: FlutterResult?
    private let store = CNContactStore()
    override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return super.application(application,didFinishLaunchingWithOptions:launchOptions)
    }
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        let channel = FlutterMethodChannel(name: "clearsafe/read_only", binaryMessenger: engineBridge.applicationRegistrar.messenger())
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            let args = call.arguments as? [String: Any] ?? [:]
            let scope = args["scope"] as? String ?? "media"
            if call.method == "permission" { result(self.access(scope)); return }
            if call.method == "requestPermission" {
                if scope == "contacts" {
                    self.store.requestAccess(for: .contacts) { _, _ in DispatchQueue.main.async {result(self.access(scope))} }
                } else {
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in DispatchQueue.main.async {result(self.access(scope))} }
                }
                return
            }
            if call.method == "selectDocuments" {
                guard self.pickerResult == nil else {result(FlutterError(code:"busy",message:"Selection in progress",details:nil));return}
                self.pickerResult=result
                let picker=UIDocumentPickerViewController(forOpeningContentTypes:[UTType.data],asCopy:false)
                picker.allowsMultipleSelection=true;picker.delegate=self
                guard let controller=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene})
                    .flatMap({$0.windows}).first(where:{$0.isKeyWindow})?.rootViewController else {
                    self.pickerResult=nil;result(FlutterError(code:"unavailable",message:"No active window",details:nil));return
                }
                controller.present(picker,animated:true);return
            }
            self.queue.async {
                do {
                    let answer: Any?
                    switch call.method {
                    case "inventory": answer = try self.inventory(offset: args["offset"] as? Int ?? 0, limit: args["limit"] as? Int ?? 200)
                    case "stat": answer = try self.stat(args["id"] as! String)
                    case "open": answer = try self.open(args["id"] as! String)
                    case "read":
                        guard let pair=self.handles[args["handle"] as! String] else {throw ReadError.unavailable}
                        answer=FlutterStandardTypedData(bytes:try pair.0.read(upToCount:65536) ?? Data())
                    case "close":
                        if let pair=self.handles.removeValue(forKey:args["handle"] as! String) {
                            try pair.0.close()
                            // Only UUID cache files created by this bridge may be removed.
                            if let url=pair.1 {try? FileManager.default.removeItem(at:url)}
                        }
                        answer=nil
                    case "contacts": answer=try self.contacts()
                    case "diagnostics":
                        var messages:[String]=[]
                        if self.access("media") != "full" {messages.append("Galeria parcial ou sem acesso; somente conteúdo autorizado.")}
                        if self.omittedComposite>0 {messages.append("\(self.omittedComposite) mídias compostas omitidas (ex.: Live Photo/RAW+JPEG).")}
                        if self.omittedUnreadable>0 {messages.append("\(self.omittedUnreadable) recursos indisponíveis localmente ou ilegíveis foram omitidos; nenhum download iCloud.")}
                        answer=messages
                    default: throw ReadError.unavailable
                    }
                    DispatchQueue.main.async { result(answer) }
                } catch { DispatchQueue.main.async {result(FlutterError(code:"read_failed",message:"Unavailable, changed, or permission revoked",details:nil))} }
            }
        }
    }
    enum ReadError: Error {case unavailable, capacity}
    private func access(_ scope:String)->String {
        if scope=="contacts" {
            switch CNContactStore.authorizationStatus(for:.contacts) {
            case .authorized:return "full"
            case .restricted:return "restricted"
            default:
                if #available(iOS 18.0, *), CNContactStore.authorizationStatus(for:.contacts) == .limited {return "limited"}
                return "denied"
            }
        }
        switch PHPhotoLibrary.authorizationStatus(for:.readWrite) {
        case .authorized:return "full"
        case .limited:return "limited"
        case .restricted:return "restricted"
        default:return "denied"
        }
    }
    private func resource(_ asset:PHAsset)->PHAssetResource? {
        let resources=PHAssetResource.assetResources(for:asset)
        // Multi-resource assets (Live Photo, edited originals, RAW+JPEG) are not
        // reduced to one component and falsely called whole-asset duplicates.
        guard resources.count==1 else {return nil}
        return resources.first
    }
    private func revision(_ asset:PHAsset)->String {
        "\(asset.modificationDate?.timeIntervalSince1970 ?? -1):\(asset.pixelWidth):\(asset.pixelHeight):\(asset.duration)"
    }
    private func measure(_ resource:PHAssetResource)throws->Int64 {
        let sem=DispatchSemaphore(value:0);var size:Int64=0;var failure:Error?
        let options=PHAssetResourceRequestOptions();options.isNetworkAccessAllowed=false
        let request=PHAssetResourceManager.default().requestData(for:resource,options:options,
            dataReceivedHandler:{data in size+=Int64(data.count)},completionHandler:{error in failure=error;sem.signal()})
        if sem.wait(timeout:.now()+120) == .timedOut {
            PHAssetResourceManager.default().cancelDataRequest(request);throw ReadError.unavailable
        }
        if let error=failure {throw error};return size
    }
    private func row(_ asset:PHAsset,_ resource:PHAssetResource,_ size:Int64)->[String:Any] {
        var m:[String:Any]=["id":asset.localIdentifier,"name":resource.originalFilename,"size":size,
            "kind":asset.mediaType == .video ? "video":"photo","folder":"","revision":revision(asset)]
        if let date=asset.modificationDate {m["modified"]=Int64(date.timeIntervalSince1970*1000)}
        return m
    }
    private func inventory(offset:Int,limit:Int)throws->[[String:Any]] {
        guard offset>=0 && limit>0 && limit<=200 else {throw ReadError.unavailable}
        let options=PHFetchOptions();options.sortDescriptors=[NSSortDescriptor(key:"creationDate",ascending:true)]
        let assets=PHAsset.fetchAssets(with:options)
        var all:[[String:Any]]=[]
        omittedComposite=0;omittedUnreadable=0
        // Enumerate eligible resources before slicing: stable pagination even with skipped assets.
        for i in 0..<assets.count {
            let asset=assets.object(at:i)
            if asset.mediaType != .image && asset.mediaType != .video {continue}
            guard let resource=resource(asset) else {omittedComposite+=1;continue}
            let key="\(asset.localIdentifier):\(revision(asset))"
            let size:Int64
            if let known=sizes[key] {size=known}
            else {do {size=try measure(resource);sizes[key]=size} catch {omittedUnreadable+=1;continue}}
            all.append(row(asset,resource,size))
        }
        for(id,url) in documents.sorted(by:{$0.key<$1.key}) {if let m=try? documentStat(id,url) {all.append(m)}}
        return Array(all.dropFirst(offset).prefix(limit))
    }
    private func documentStat(_ id:String,_ url:URL)throws->[String:Any] {
        let granted=url.startAccessingSecurityScopedResource();defer {if granted {url.stopAccessingSecurityScopedResource()}}
        let values=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey,.nameKey,.contentTypeKey])
        let type=values.contentType
        let kind=type?.conforms(to:.image)==true ? "photo" :
            type?.conforms(to:.movie)==true ? "video" :
            type?.conforms(to:.audio)==true ? "audio" :
            (type?.conforms(to:.text)==true || type?.conforms(to:.pdf)==true || type?.conforms(to:.archive)==true) ? "document" : "other"
        var item:[String:Any]=["id":id,"name":values.name ?? "Document","size":values.fileSize ?? -1,
            "kind":kind,"folder":"Documentos selecionados","revision":"unversioned"]
        if let date=values.contentModificationDate {item["modified"]=Int64(date.timeIntervalSince1970*1000)}
        return item
    }
    private func stat(_ id:String)throws->[String:Any]? {
        if let url=documents[id] {return try documentStat(id,url)}
        guard let asset=PHAsset.fetchAssets(withLocalIdentifiers:[id],options:nil).firstObject,
              let resource=resource(asset) else {return nil}
        guard let size=sizes["\(id):\(revision(asset))"] else {return nil}
        return row(asset,resource,size)
    }
    private func open(_ id:String)throws->String {
        let handle=UUID().uuidString
        if let url=documents[id] {
            // Read selected documents directly without copying originals.
            guard url.startAccessingSecurityScopedResource() else {throw ReadError.unavailable}
            defer {url.stopAccessingSecurityScopedResource()}
            handles[handle]=(try FileHandle(forReadingFrom:url),nil);return handle
        }
        guard let asset=PHAsset.fetchAssets(withLocalIdentifiers:[id],options:nil).firstObject,
              let resource=resource(asset),let size=sizes["\(id):\(revision(asset))"] else {throw ReadError.unavailable}
        // Bound sandbox scratch usage; two comparison streams may be open.
        let cap:Int64=512*1024*1024
        guard size<=cap else {throw ReadError.capacity}
        let cache=FileManager.default.temporaryDirectory.appendingPathComponent("clearsafe-read",isDirectory:true)
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        let volume=try cache.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey])
        guard (volume.volumeAvailableCapacityForImportantUsage ?? 0)>size+64*1024*1024 else {throw ReadError.capacity}
        let url=cache.appendingPathComponent(UUID().uuidString)
        let sem=DispatchSemaphore(value:0);var failure:Error?
        let opts=PHAssetResourceRequestOptions();opts.isNetworkAccessAllowed=false
        PHAssetResourceManager.default().writeData(for:resource,toFile:url,options:opts) {error in failure=error;sem.signal()}
        sem.wait()
        if let error=failure {try? FileManager.default.removeItem(at:url);throw error}
        do {handles[handle]=(try FileHandle(forReadingFrom:url),url)}
        catch {try? FileManager.default.removeItem(at:url);throw error}
        return handle
    }
    private func contacts()throws->[[String:Any]] {
        guard access("contacts")=="full" || access("contacts")=="limited" else {throw ReadError.unavailable}
        let request=CNContactFetchRequest(keysToFetch:[CNContactIdentifierKey,CNContactGivenNameKey,
            CNContactFamilyNameKey,CNContactPhoneNumbersKey,CNContactEmailAddressesKey] as [CNKeyDescriptor])
        var out:[[String:Any]]=[]
        try store.enumerateContacts(with:request) {c,_ in out.append(["id":c.identifier,
            "name":"\(c.givenName) \(c.familyName)","phones":c.phoneNumbers.map{$0.value.stringValue},
            "emails":c.emailAddresses.map{String($0.value)}])}
        return out
    }
    func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
        queue.async {for url in urls {self.documents["document:\(url.absoluteString)"]=url}
            DispatchQueue.main.async {self.pickerResult?(nil);self.pickerResult=nil}}
    }
    func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {pickerResult?(nil);pickerResult=nil}
}
