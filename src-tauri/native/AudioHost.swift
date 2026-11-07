import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import ScreenCaptureKit
import CoreMedia

// The C boundary exchanges JSON only. Audio and credentials are never written to disk.
typealias EventCallback = @convention(c) (UnsafePointer<CChar>) -> Void
private var callback: EventCallback?
private func send(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value),
          let text = String(data: data, encoding: .utf8) else { return }
    text.withCString { callback?($0) }
}
@_cdecl("fl_audio_init") public func audioInit(_ cb: @escaping @convention(c) (UnsafePointer<CChar>) -> Void) {
    callback = cb
    DispatchQueue.main.async { AudioHost.shared.observeDevices() }
}
@_cdecl("fl_audio_command") public func audioCommand(_ json: UnsafePointer<CChar>) {
    let text = String(cString: json)
    guard let data = text.data(using: .utf8), let cmd = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    DispatchQueue.main.async { AudioHost.shared.command(cmd) }
}
private final class AudioHost: NSObject, SCStreamOutput, SCStreamDelegate {
    static let shared = AudioHost()
    private var engine = AVAudioEngine()
    private let output = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private let queue = DispatchQueue(label: "live.pcm")
    private var stream: SCStream?
    private var tap = false
    private var epoch = 0
    private var requested = false
    private var uid = ""
    private var deviceID: AudioDeviceID = 0
    private var observer: NSObjectProtocol?
    private var restart: DispatchWorkItem?
    private var listener: AudioObjectPropertyListenerBlock?
    private var playback = PlaybackBudget()
    // Converter and input bytes are confined to queue.
    private var converter: AVAudioConverter?
    private var format: AVAudioFormat?
    private var convertedEpoch = -1
    private var pending = Data()
    override init() {
        super.init()
        output.attach(player)
        output.connect(player, to: output.mainMixerNode, format: outputFormat)
    }
    func command(_ c: [String: Any]) {
        switch c["op"] as? String {
        case "devices": devicesEvent()
        case "start":
            stop(); uid = c["uid"] as? String ?? ""
            let e = epoch
            Task { @MainActor in
                do {
                    if c["source"] as? String == "system" { try await self.startSystem(e) }
                    else {
                        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                        guard e == self.epoch else { return }
                        guard allowed else { throw self.error("마이크 권한을 허용해 주세요. 시스템 설정 → 개인정보 보호 및 보안 → 마이크") }
                        self.requested = true
                        try self.startMic()
                    }
                    if e == self.epoch { send(["type":"ready"]) }
                } catch { if e == self.epoch { self.stop(); send(["type":"error", "message":error.localizedDescription]) } }
            }
        case "stop": stop()
        case "play":
            if let raw = c["data"] as? String,
               raw.utf8.count <= PlaybackBudget.maxFrames * 2 * 4 / 3 + 4,
               let bytes = Data(base64Encoded: raw) { play(bytes) }
            else { outputFailure("음성 출력 데이터가 잘못되었거나 출력 한도를 초과했습니다.") }
        case "clear": clear()
        case "volume": player.volume = Float(c["value"] as? Double ?? 0.7)
        default: break
        }
    }
    private func error(_ message: String) -> NSError { NSError(domain: "LiveAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    private func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain)
    }
    private func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String {
        var a=address(selector), size=UInt32(MemoryLayout<CFString>.size); var v: CFString="" as CFString
        let code=withUnsafeMutablePointer(to:&v) { AudioObjectGetPropertyData(id,&a,0,nil,&size,$0) }
        return code == noErr ? v as String : ""
    }
    private func defaultDevice() -> AudioDeviceID {
        var a=address(kAudioHardwarePropertyDefaultInputDevice), size=UInt32(MemoryLayout<AudioDeviceID>.size); var id: AudioDeviceID=0
        _=AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,&id); return id
    }
    private func devices() -> [[String: Any]] {
        var a=address(kAudioHardwarePropertyDevices), size: UInt32=0; let system=AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system,&a,0,nil,&size)==noErr,size>0 else {return []}
        var ids=[AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
        let code=ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(system,&a,0,nil,&size,$0.baseAddress!) }
        guard code==noErr else{return []}
        let current=defaultDevice()
        return ids.compactMap { id in
            var hidden=UInt32(0), hiddenSize=UInt32(4), hiddenAddress=address(kAudioDevicePropertyIsHidden)
            _=AudioObjectGetPropertyData(id,&hiddenAddress,0,nil,&hiddenSize,&hidden)
            guard hidden==0 else{return nil}
            var a=address(kAudioDevicePropertyStreamConfiguration,kAudioDevicePropertyScopeInput), size: UInt32=0
            guard AudioObjectGetPropertyDataSize(id,&a,0,nil,&size)==noErr,size>0 else{return nil}
            let p=UnsafeMutableRawPointer.allocate(byteCount:Int(size),alignment:MemoryLayout<AudioBufferList>.alignment);defer{p.deallocate()}
            guard AudioObjectGetPropertyData(id,&a,0,nil,&size,p)==noErr else{return nil}
            let list=UnsafeMutableAudioBufferListPointer(p.assumingMemoryBound(to:AudioBufferList.self))
            guard list.contains(where:{$0.mNumberChannels>0}) else{return nil}
            return ["id":Int(id),"uid":string(id,kAudioDevicePropertyDeviceUID),"name":string(id,kAudioObjectPropertyName),"isDefault":id==current]
        }
    }
    private func devicesEvent(){send(["type":"devices","devices":devices()])}
    func observeDevices() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _,_ in
            guard let self=self else{return}; self.devicesEvent()
            let target=self.uid.isEmpty ? self.defaultDevice() : AudioDeviceID(self.devices().first(where:{$0["uid"] as? String==self.uid})?["id"] as? Int ?? 0)
            if self.requested && target != self.deviceID {self.scheduleRestart()}
        }
        listener=block
        for s in [kAudioHardwarePropertyDevices,kAudioHardwarePropertyDefaultInputDevice] {
            var a=address(s);AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&a,.main,block)
        }
    }
    private func stopEngine(){
        if let o=observer {NotificationCenter.default.removeObserver(o);observer=nil}
        engine.stop();if tap {engine.inputNode.removeTap(onBus:0);tap=false}
    }
    private func startMic() throws {
        stopEngine()
        var id=defaultDevice()
        if !uid.isEmpty {
            guard let value=devices().first(where:{$0["uid"] as? String==uid})?["id"] as? Int else {throw error("선택한 마이크가 연결되어 있지 않습니다.")}
            id=AudioDeviceID(value)
        }
        guard id != 0 else{throw error("연결된 마이크가 없습니다.")}
        deviceID=id;let node=engine.inputNode
        guard let unit=node.audioUnit,AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&id,UInt32(MemoryLayout<AudioDeviceID>.size))==noErr else{throw error("마이크를 열지 못했습니다.")}
        let f=node.outputFormat(forBus:0);guard f.sampleRate>0,f.channelCount>0 else{throw error("마이크가 아직 준비되지 않았습니다.")}
        let e=epoch
        node.installTap(onBus:0,bufferSize:1024,format:f){[weak self] b,_ in
            guard let self=self,let copy=AVAudioPCMBuffer(pcmFormat:b.format,frameCapacity:b.frameLength) else{return}
            copy.frameLength=b.frameLength
            let src=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:b.audioBufferList)),dst=UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for i in 0..<src.count {if let from=src[i].mData,let to=dst[i].mData{memcpy(to,from,Int(src[i].mDataByteSize))}}
            self.queue.async{self.convert(copy,e)}
        }
        tap=true;try engine.start()
        observer=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:.main){[weak self] _ in
            guard let self=self,!self.engine.isRunning else{return};self.scheduleRestart()
        }
    }
    private func scheduleRestart(){
        guard requested else{return};restart?.cancel()
        let work=DispatchWorkItem{[weak self] in
            guard let self=self,self.requested else{return};self.epoch += 1
            do{try self.startMic()}catch{self.stop();send(["type":"error","message":"마이크 연결이 변경됐습니다. 장치를 확인하고 다시 시작해 주세요."])}
        };restart=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
    }
    private func stop(){epoch += 1;requested=false;restart?.cancel();stopEngine();if let old=stream{stream=nil;Task{try? await old.stopCapture()}}}
    private func startSystem(_ e:Int) async throws {
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        guard e==epoch else{return};guard let display=content.displays.first else{throw error("캡처할 화면이 없습니다.")}
        let config=SCStreamConfiguration();config.capturesAudio=true;config.excludesCurrentProcessAudio=true;config.sampleRate=48000;config.channelCount=1;config.width=2;config.height=2;config.minimumFrameInterval=CMTime(value:1,timescale:1)
        let s=SCStream(filter:SCContentFilter(display:display,excludingWindows:[]),configuration:config,delegate:self)
        try s.addStreamOutput(self,type:.audio,sampleHandlerQueue:queue);stream=s;try await s.startCapture();if e != epoch {try? await s.stopCapture()}
    }
    func stream(_ stream:SCStream,didOutputSampleBuffer sampleBuffer:CMSampleBuffer,of type:SCStreamOutputType){
        guard type == .audio,sampleBuffer.isValid,let desc=CMSampleBufferGetFormatDescription(sampleBuffer),let asbd=CMAudioFormatDescriptionGetStreamBasicDescription(desc),let f=AVAudioFormat(streamDescription:asbd) else{return}
        let count=CMSampleBufferGetNumSamples(sampleBuffer);guard count>0,let b=AVAudioPCMBuffer(pcmFormat:f,frameCapacity:AVAudioFrameCount(count)) else{return}
        b.frameLength=AVAudioFrameCount(count);guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer,at:0,frameCount:Int32(count),into:b.mutableAudioBufferList)==noErr else{return}
        DispatchQueue.main.async{[weak self] in guard let self=self,self.stream === stream else{return};let e=self.epoch;self.queue.async{self.convert(b,e)}}
    }
    func stream(_ stream:SCStream,didStopWithError error:Error){DispatchQueue.main.async{[weak self] in guard let self=self,self.stream === stream else{return};self.stop();send(["type":"error","message":"시스템 오디오 캡처가 중단됐습니다. 녹음 권한을 확인해 주세요."])}}
    private func convert(_ b:AVAudioPCMBuffer,_ e:Int){
        guard e>=convertedEpoch else{return}
        if e != convertedEpoch || format != b.format {convertedEpoch=e;format=b.format;converter=AVAudioConverter(from:b.format,to:AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:true)!);pending.removeAll()}
        guard let c=converter,let dest=AVAudioPCMBuffer(pcmFormat:c.outputFormat,frameCapacity:AVAudioFrameCount(ceil(Double(b.frameLength)*16000/b.format.sampleRate)+32)) else{return}
        var once=false;var error:NSError?
        c.convert(to:dest,error:&error){_,status in if once{status.pointee = .noDataNow;return nil};once=true;status.pointee = .haveData;return b}
        guard error==nil,let ptr=dest.int16ChannelData?[0],dest.frameLength>0 else{return}
        pending.append(Data(bytes:ptr,count:Int(dest.frameLength)*2))
        while pending.count>=640 {
            let chunk=Data(pending.prefix(640));pending.removeFirst(640)
            DispatchQueue.main.async{[weak self] in guard self?.epoch==e else{return};send(["type":"pcm","data":chunk.base64EncodedString()])}
        }
    }
    private func clear(){playback.clear();player.stop()}
    private func outputFailure(_ message: String){
        guard !playback.failed else {return}
        playback.fail();player.stop()
        send(["type":"output-error","message":message + " 음성 출력을 껐습니다. 자막과 입력은 계속됩니다. 다시 켜서 재시도할 수 있습니다."])
    }
    private func play(_ data:Data){
        guard !playback.failed else {return}
        let n=data.count/2
        guard n>0,data.count%2==0 else {outputFailure("음성 출력 데이터가 올바른 PCM 형식이 아닙니다.");return}
        guard let ticket=playback.admit(n) else {outputFailure("음성 출력 대기량이 한도(30초 또는 4096개 조각)를 초과해 대기 중인 음성을 취소했습니다.");return}
        guard let b=AVAudioPCMBuffer(pcmFormat:outputFormat,frameCapacity:AVAudioFrameCount(n)),let dst=b.floatChannelData?[0] else {outputFailure("음성 출력 버퍼를 만들지 못했습니다.");return}
        b.frameLength=AVAudioFrameCount(n);data.withUnsafeBytes{raw in for i in 0..<n{dst[i]=Float(Int16(bitPattern:UInt16(raw[i*2]) | UInt16(raw[i*2+1])<<8))/32768}}
        do{if !output.isRunning{try output.start()}}catch{outputFailure("음성 출력을 시작하지 못했습니다.");return}
        player.scheduleBuffer(b,completionCallbackType:.dataPlayedBack){[weak self] _ in DispatchQueue.main.async{self?.playback.complete(ticket)}}
        if !player.isPlaying{player.play()}
    }
}
