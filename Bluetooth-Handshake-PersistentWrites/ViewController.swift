//
//  ViewController.swift
//  Bluetooth-Handshake-PersistentWrites
//
//  Created by Raul Mena on 3/2/19.
//  Copyright © 2019 Raul Mena. All rights reserved.
//

import UIKit
import CoreBluetooth

class ViewController: UIViewController {
    
    @IBOutlet weak var numberOfPeripherals: UILabel!
    @IBOutlet weak var textView: UITextView!
    
    var manager: BluetoothManager?
    
    var registeredDevices = [UUID]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        manager = BluetoothManager()
        manager?.delegate = self
        
        textView.isEditable = false
        textView.font = UIFont.systemFont(ofSize: 12)
    }
    
    @IBAction func startScan(_ sender: Any) {
        manager?.centralManager.scanForPeripherals(withServices: [CBUUID(string: "FD25")], options: nil)
    }
    
    @IBAction func StopScan(_ sender: Any) {
        manager?.centralManager.stopScan()
    }
    
}


extension ViewController: PeripheralUpdateDelegate{
    
    func handleCharacteristicUpdate(identifier: UUID) {
        
        if !registeredDevices.contains(identifier){
            
            registeredDevices.append(identifier)
            guard let integer = numberOfPeripherals.text else {return}
            guard var number = Int(integer) else {return}
            number += 1
            let text = String(number)
            
            self.numberOfPeripherals.text = text
            
            guard var uuids = textView.text else {return}
            uuids.append("\n")
            uuids.append(identifier.uuidString)
            textView.text = uuids
        }
        
    }
    
}
