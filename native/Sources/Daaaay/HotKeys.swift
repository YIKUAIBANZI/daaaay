import Carbon

@MainActor
final class HotKeys {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onPress: ((UInt32)->Void)?
    func register() -> String? {
        var event=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let status=InstallEventHandler(GetApplicationEventTarget(),{ _,event,context in
            guard let event,let context else { return OSStatus(eventNotHandledErr) }
            var id=EventHotKeyID()
            let status=GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
            guard status == noErr else { return status }
            let owner=Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.onPress?(id.id) }
            return noErr
        },1,&event,Unmanaged.passUnretained(self).toOpaque(),&handler)
        guard status == noErr else { return "快捷键注册失败，请使用菜单栏入口。" }
        var failed: [String]=[]
        for (id,key,label) in [(UInt32(1),UInt32(kVK_Space),"⌃⌥Space"),(UInt32(2),UInt32(kVK_ANSI_D),"⌃⌥D")] {
            var ref: EventHotKeyRef?
            let result=RegisterEventHotKey(key,UInt32(controlKey|optionKey),EventHotKeyID(signature:0x44415959,id:id),GetApplicationEventTarget(),0,&ref)
            if result == noErr,let ref { references.append(ref) } else { failed.append(label) }
        }
        return failed.isEmpty ? nil : "\(failed.joined(separator:"、")) 已被占用，请使用菜单栏入口。"
    }
    func unregister() {
        for ref in references { UnregisterEventHotKey(ref) }; references=[]
        if let handler { RemoveEventHandler(handler) }; handler=nil
    }
}
