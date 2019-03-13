//
//  BluetoothManager.swift
//  Bluetooth-Handshake-PersistentWrites
//
//  Created by Raul Mena on 3/2/19.
//  Copyright © 2019 Raul Mena. All rights reserved.
//




import UserNotifications
import UIKit
import CoreBluetooth


protocol PeripheralUpdateDelegate {
    func handleCharacteristicUpdate(identifier: UUID)
}

struct ConnectedPeripheral{
    var peripheral: CBPeripheral?
    var phoneCharacteristic: CBCharacteristic?
    var confirmationCharacteristic: CBCharacteristic?
    var responseCharacteristic: CBCharacteristic?
    
    var centralPhoneFound = false
    
    init(peripheral: CBPeripheral){
        self.peripheral = peripheral
    }
}

struct ConnectedCentral{
    var confirmation: Bool?
}

class BluetoothManager: NSObject {
    
    var delegate: PeripheralUpdateDelegate?
    
    // User's phone number
    var advertisedPhone: Data? = "+1 7863673222".data(using: .utf8)
    
    var centralPhone: Data? = "+1 3052225555".data(using: .utf8)
    
    // Positive confirmation
    var positiveConfirmation: Data? = "yes".data(using: .utf8)
    
    // Negative confirmation
    var negativeConfirmation: Data? = "no".data(using: .utf8)
    
    
    // Current peripheral
    var connectedPeripheral: ConnectedPeripheral?
    
    // queue
    var queue = [CBPeripheral]()
    
    // Current central
    var connectedCentral: ConnectedCentral?
    
    // Recently Discovered
    var discoveredDevices = [CBPeripheral: Bool]()
    var handshakeWasSuccessfulFor = [CBPeripheral: Bool]()
    
    let UserPhoneCharacteristicUUID = CBUUID.init(string: "32D28D64-3B88-41B4-8138-4C183D93EF79")
    let ConfirmationCharacteristicUUID = CBUUID.init(string: "B746B607-447C-40B0-B066-3697431920C3")
    let PeripheralResponseCharacteristicUUID = CBUUID.init(string: "55F4A4A0-F837-45D2-92B9-C6C2FB5000E0")
    
    let serviceUUID = CBUUID(string: "B42D832B-49BD-421E-9A93-19326801E6A7")
    let advertisementServiceUUID = CBUUID(string: "FD25")
    
    var service: CBMutableService!
    var phoneCharacteristic: CBMutableCharacteristic!
    var confirmationCharacteristic: CBMutableCharacteristic!
    var peripheralResponseCharacteristic: CBMutableCharacteristic!
    
    var peripheralManager: CBPeripheralManager!
    var centralManager: CBCentralManager!
    var timer: RepeatingTimer?
    
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
    }
    
    fileprivate func processPhoneNumber(number: String){
        /*   Central searches peripheral's phone number in its directory
         */
        
        guard let peripheral = connectedPeripheral?.peripheral else {return}
        guard let confirmationCharacteristic = connectedPeripheral?.confirmationCharacteristic else {return}
        guard let centralPhone = centralPhone else {return}
        
        connectedCentral = ConnectedCentral(confirmation: true)
        print("Attempting to write")
        peripheral.writeValue(centralPhone, for: confirmationCharacteristic, type: CBCharacteristicWriteType.withResponse)
    }
    
    var queueIsBeenProcessed = false
    
    fileprivate func processQueue(){
        print("Processing queue")
        if let peripheral = queue.first{
            if handshakeWasSuccessfulFor[peripheral] ?? false{
                queue.removeFirst()
                print("elements in queue: \(queue.count)")
                if !queue.isEmpty{
                    processQueue()
                }
                else{
                    queueIsBeenProcessed = false
                }
            }
            else{
                connectedPeripheral = ConnectedPeripheral(peripheral: peripheral)
                centralManager.connect(peripheral, options: nil)
            }
        }
    }
    
} // end CustomBluetoothClass


/*  Peripheral Role
 */
extension BluetoothManager: CBPeripheralManagerDelegate {
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        
        // if bluetooth is on
        if peripheral.state == .poweredOn {
            // instantiate service
            service = CBMutableService(type: serviceUUID, primary: true)
            
            phoneCharacteristic = CBMutableCharacteristic(type: UserPhoneCharacteristicUUID, properties: [.read], value: nil, permissions: .readable)
            
            confirmationCharacteristic = CBMutableCharacteristic(type: ConfirmationCharacteristicUUID, properties: [.write], value: nil, permissions: .writeable)
            
            peripheralResponseCharacteristic = CBMutableCharacteristic(type: PeripheralResponseCharacteristicUUID, properties: [.read], value: nil, permissions: .readable)
            
            // Add characteristics to service
            service.characteristics = [phoneCharacteristic!, confirmationCharacteristic!, peripheralResponseCharacteristic!]
            // Add service to Peripheral Manager
            peripheralManager?.add(service!)
            peripheralManager?.delegate = self
            let adData = [CBAdvertisementDataLocalNameKey:"This Is FrienDetect Service", CBAdvertisementDataServiceUUIDsKey:[advertisementServiceUUID]] as [String:Any]
            peripheralManager?.startAdvertising(adData)
            
        }
    }
    
    // Read request from central
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("Read request received")
        if request.characteristic.uuid == phoneCharacteristic.uuid{
            phoneCharacteristic.value = advertisedPhone
            
            guard let length = phoneCharacteristic.value?.count else {return}
            
            if request.offset > length{
                peripheralManager.respond(to: request, withResult: CBATTError.Code.invalidOffset)
                print("ERROR: Invalid read request - invalid offset")
                return
            }
            
            let range = request.offset..<length - request.offset
            request.value = phoneCharacteristic.value?.subdata(in: range)
            
            peripheralManager.respond(to: request, withResult: CBATTError.Code.success)
            
        }
        else if request.characteristic.uuid == peripheralResponseCharacteristic.uuid{
            
            if connectedPeripheral?.centralPhoneFound == true{
                peripheralResponseCharacteristic.value = positiveConfirmation
            }
            else{
                peripheralResponseCharacteristic.value = negativeConfirmation
            }
            
            guard let length = peripheralResponseCharacteristic.value?.count else {return}
            
            if request.offset > length{
                peripheralManager.respond(to: request, withResult: CBATTError.Code.invalidOffset)
                print("ERROR: Invalid read request - invalid offset")
                return
            }
            
            let range = request.offset..<length - request.offset
            request.value = peripheralResponseCharacteristic.value?.subdata(in: range)
            
            peripheralManager.respond(to: request, withResult: CBATTError.Code.success)
            
            /*  Alert user
             */
            print("handshake I'm a peripheral - Central_Id: \(request.central.identifier)")
            delegate?.handleCharacteristicUpdate(identifier: request.central.identifier)
        }
    }
    
    // Write request from Central
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        print("Write request received")
        let request = requests[0]
        if request.characteristic.uuid == confirmationCharacteristic.uuid{
            
            confirmationCharacteristic.value = request.value
            
            guard let value = request.value else{
                print("ERROR reading request value")
                return
            }
            
            let centralPhone = String(data: value, encoding: .utf8)
            print("centralPhone: \(centralPhone)")
            if centralPhone == "no"{
                /*  Central should cancel connection
                 No user notification
                 */
            }
            else{
                /*  peripheral searches central's phone in its directory
                 */
                
                /*  peripheral found central's phone
                 */
                connectedPeripheral?.centralPhoneFound = true
            }
            peripheralManager.respond(to: request, withResult: CBATTError.Code.success)
        }
    }
}

/*  Central role
 */
extension BluetoothManager: CBCentralManagerDelegate, CBPeripheralDelegate{
    
    // Scan for Peripherals
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [CBUUID(string: "FD25")], options: nil)
        }
    }
    
    // Did Discover Peripheral
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        //            timer = RepeatingTimer(timeInterval: 1)
        //            timer?.eventHandler = {
        //                print("Here")
        //            }
        //            timer?.resume()
        
        if let alreadyDiscovered = discoveredDevices[peripheral]{
            return
        }
        else{
            print("enqueing")
            discoveredDevices[peripheral] = true
            queue.append(peripheral)
            if !queueIsBeenProcessed{
                queueIsBeenProcessed = true
                processQueue()
            }
        }
    }
    
    // Did Connect
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    // Did Discover Services
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        if let services = peripheral.services{
            for svc in services{
                if svc.uuid == serviceUUID{
                    peripheral.discoverCharacteristics([UserPhoneCharacteristicUUID, ConfirmationCharacteristicUUID, PeripheralResponseCharacteristicUUID], for: svc)
                }
            }
        }
    }
    
    // Did Discover Characteristics
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        if let error = error{
            print("ERROR discovering characteristic: \(error.localizedDescription)")
            return
        }
        
        if let characteristics = service.characteristics{
            for char in characteristics{
                if char.uuid == ConfirmationCharacteristicUUID{
                    connectedPeripheral?.confirmationCharacteristic = char
                }
                else if char.uuid == PeripheralResponseCharacteristicUUID{
                    connectedPeripheral?.responseCharacteristic = char
                }
                else if char.uuid == UserPhoneCharacteristicUUID{
                    
                    connectedPeripheral?.phoneCharacteristic = char
                }
            }
            guard let char = connectedPeripheral?.phoneCharacteristic else {return}
            print("Attempting to read Phone Number")
            peripheral.readValue(for: char)
        }
        
    }
    
    // Peripheral Updated Value Of Characteristic
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error{
            print("ERROR reading value from peripheral: \(error.localizedDescription)")
            return
        }
        
        if characteristic.uuid == UserPhoneCharacteristicUUID{
            if let data = characteristic.value{
                guard let phoneNumber = String(data: data, encoding: .utf8) else {
                    print("Failed to read peripheral phone number")
                    return
                }
                print("Phone number: \(phoneNumber)")
                processPhoneNumber(number: phoneNumber)
            }
            
        }
        else if characteristic.uuid == PeripheralResponseCharacteristicUUID{
            if let data = characteristic.value{
                guard let response = String(data: data, encoding: .utf8) else {
                    print("Failed to read peripheral response")
                    return
                }
                if response == "yes"{
                    /*  Alert user
                     */
                    
                    
                    delegate?.handleCharacteristicUpdate(identifier: peripheral.identifier)
                    print("handshake I'm a central - Peripheral_Id: \(peripheral.identifier)")
                    
                    handshakeWasSuccessfulFor[peripheral] = true
                    queueIsBeenProcessed = false
                    if !queue.isEmpty{
                        queueIsBeenProcessed = true
                        processQueue()
                    }
                }
                /*  Disconnect
                 */
                centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if let error = error{
            print("Error writing to characteristic: \(error.localizedDescription)")
            return
        }
        
        if connectedCentral?.confirmation == false{
            /*  Central didn't find peripheral's phone in its directory
             cancel connection
             */
            centralManager.cancelPeripheralConnection(peripheral)
        }
        else{
            /*  Central found peripheral's phone
             request peripheral's confirmation
             */
            guard let char = connectedPeripheral?.responseCharacteristic else {return}
            print("Attempt to read peripheral's response")
            peripheral.readValue(for: char)
        }
    }
    
    // Error On Subscribing to Characteristic
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error{
            print("ERROR subscribing: \(error)")
        }
    }
    
    // Did Disconnect From Peripheral
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Peripheral disconnected: \(peripheral)")
        
        if let handshakeSuccessful = handshakeWasSuccessfulFor[peripheral]{
            if !handshakeSuccessful{
                print("Reconnecting to: \(peripheral)")
                queueIsBeenProcessed = true
                processQueue()
            }
        }
        else{
            print("Reconnecting to: \(peripheral)")
            queueIsBeenProcessed = true
            processQueue()
        }
        
    }
    
}

class RepeatingTimer {
    
    let timeInterval: TimeInterval
    
    init(timeInterval: TimeInterval) {
        self.timeInterval = timeInterval
    }
    
    private lazy var timer: DispatchSourceTimer = {
        let t = DispatchSource.makeTimerSource(flags: .init(rawValue: 0), queue: DispatchQueue.main)
        t.schedule(deadline: .now() + self.timeInterval, repeating: self.timeInterval)
        t.setEventHandler(handler: { [weak self] in
            self?.eventHandler?()
        })
        return t
    }()
    
    var eventHandler: (() -> Void)?
    
    private enum State {
        case suspended
        case resumed
    }
    
    private var state: State = .suspended
    
    deinit {
        timer.setEventHandler {}
        timer.cancel()
        /*
         If the timer is suspended, calling cancel without resuming
         triggers a crash. This is documented here https://forums.developer.apple.com/thread/15902
         */
        resume()
        eventHandler = nil
    }
    
    func resume() {
        if state == .resumed {
            return
        }
        state = .resumed
        timer.resume()
    }
    
    func suspend() {
        if state == .suspended {
            return
        }
        state = .suspended
        timer.suspend()
    }
}

