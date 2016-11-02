//
//  ShadowPeripheral.swift
//  Blues
//
//  Created by Vincent Esche on 28/10/2016.
//  Copyright © 2016 NWTN Berlin. All rights reserved.
//

import Foundation
import CoreBluetooth

public class ShadowPeripheral: NSObject {
    public let uuid: Identifier
    let core: CBPeripheral
    weak var peripheral: Peripheral?
    var connectionOptions: ConnectionOptions?
    var services: [Identifier: Service] = [:]
    weak var centralManager: CentralManager?

    init(core: CBPeripheral, centralManager: CentralManager) {
        self.uuid = Identifier(uuid: core.identifier)
        self.core = core
        self.centralManager = centralManager
        super.init()
        self.core.delegate = self
    }

    var queue: DispatchQueue {
        guard let centralManager = self.centralManager else {
            fatalError("Invalid use of detached ShadowPeripheral")
        }
        return centralManager.queue
    }

    func inner(for peripheral: Peripheral) -> CBPeripheral {
        guard peripheral === peripheral else {
            fatalError("Attempting to access unknown Peripheral")
        }
        return self.core
    }

    func wrapperOf(peripheral: CBPeripheral) -> Peripheral? {
        return self.peripheral
    }

    func wrapperOf(service: CBService) -> Service? {
        return self.services[Identifier(uuid: service.uuid)]
    }

    func wrapperOf(characteristic: CBCharacteristic) -> Characteristic? {
        return self.wrapperOf(service: characteristic.service).flatMap {
            $0.characteristics[Identifier(uuid: characteristic.uuid)]
        }
    }

    func wrapperOf(descriptor: CBDescriptor) -> Descriptor? {
        return self.wrapperOf(characteristic: descriptor.characteristic).flatMap {
            $0.descriptors[Identifier(uuid: descriptor.uuid)]
        }
    }

    func attach() {
        guard let cores = self.core.services else {
            return
        }
        for core in cores {
            let uuid = Identifier(uuid: core.uuid)
            guard let service = self.services[uuid] else {
                continue
            }
            service.shadow.attach(core: core)
        }
    }

    func detach() {
        for service in self.services.values {
            service.shadow.detach()
        }
    }
}

extension ShadowPeripheral: Responder {
    public var nextResponder: Responder? {
        return self.centralManager
    }
}

extension ShadowPeripheral: PeripheralHandling {

    func dummyVoidResult() -> Result<(), PeripheralError> {
        if self.core.state == .connected {
            return .ok(())
        } else {
            return .err(.unreachable)
        }
    }

    func discover(services: [CBUUID]?) -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.discoverServices(services)
        }
    }

    func discover(includedServices: [CBUUID]?, for service: CBService) -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.discoverIncludedServices(includedServices, for: service)
        }
    }

    func discover(characteristics: [CBUUID]?, for service: CBService) -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.discoverCharacteristics(characteristics, for: service)
        }
    }

    func discoverDescriptors(for characteristic: CBCharacteristic) -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.discoverDescriptors(for: characteristic)
        }
    }

    func readData(for characteristic: CBCharacteristic) -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.readValue(for: characteristic)
        }
    }

    func readData(for descriptor: CBDescriptor) -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.readValue(for: descriptor)
        }
    }

    func write(data: Data, for characteristic: CBCharacteristic, type: WriteType) -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.writeValue(data, for: characteristic, type: type.inner)
        }
    }

    func write(data: Data, for descriptor: CBDescriptor) -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.writeValue(data, for: descriptor)
        }
    }

    func set(notifyValue: Bool, for characteristic: CBCharacteristic) -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.setNotifyValue(notifyValue, for: characteristic)
        }
    }

    func readRSSI() -> Result<(), PeripheralError> {
        return self.dummyVoidResult().map {
            self.core.readRSSI()
        }
    }
}

extension ShadowPeripheral: CBPeripheralDelegate {

    public func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(peripheral: peripheral) else {
                return
            }
            wrapper.didUpdate(name: peripheral.name, ofPeripheral: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(peripheral: peripheral) else {
                return
            }
            let shadowServices = invalidatedServices.map {
                ShadowService(core: $0, peripheral: wrapper)
            }
            let services = shadowServices.map { shadowService -> Service in
                let service = wrapper.makeService(shadow: shadowService)
                wrapper.shadow.services[shadowService.uuid] = service
                return service
            }
            wrapper.didModify(services: services, ofPeripheral: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI rssi: NSNumber, error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(peripheral: peripheral) else {
                return
            }
            let rssi = (rssi != 0) ? rssi as Int : nil
            let result = Result(success: rssi, failure: error)
            wrapper.didRead(rssi: result, ofPeripheral: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(peripheral: peripheral) else {
                return
            }
            let coreServices = Result(success: peripheral.services, failure: error)
            let shadowServices = coreServices.map { coreServices in
                coreServices.map {
                    ShadowService(core: $0, peripheral: wrapper)
                }
            }
            let services = shadowServices.map { shadowServices -> [Service] in
                shadowServices.map { shadowService in
                    let service = wrapper.makeService(shadow: shadowService)
                    wrapper.shadow.services[shadowService.uuid] = service
                    return service
                }
            }
            wrapper.didDiscover(services: services, forPeripheral: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let peripheral = self.peripheral else {
                return
            }
            guard let wrapper = self.wrapperOf(service: service) else {
                return
            }
            let coreServices = Result(success: service.includedServices, failure: error)
            let shadowServices = coreServices.map { coreServices in
                coreServices.map {
                    ShadowService(core: $0, peripheral: peripheral)
                }
            }
            let services = shadowServices.map { shadowServices -> [Service] in
                shadowServices.map { shadowService in
                    let service = peripheral.makeService(shadow: shadowService)
                    peripheral.shadow.services[shadowService.uuid] = service
                    wrapper.shadow.includedServices[shadowService.uuid] = service
                    return service
                }
            }
            wrapper.didDiscover(includedServices: services, forService: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(service: service) else {
                return
            }
            let coreCharacteristics = Result(success: service.characteristics, failure: error)
            let shadowCharacteristics = coreCharacteristics.map { coreCharacteristics in
                coreCharacteristics.map {
                    ShadowCharacteristic(core: $0, service: wrapper)
                }
            }
            let characteristics = shadowCharacteristics.map { shadowCharacteristics -> [Characteristic] in
                shadowCharacteristics.map { shadowCharacteristic in
                    let characteristic = wrapper.makeCharacteristic(shadow: shadowCharacteristic)
                    wrapper.shadow.characteristics[shadowCharacteristic.uuid] = characteristic
                    return characteristic
                }
            }
            wrapper.didDiscover(characteristics: characteristics, forService: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(characteristic: characteristic) else {
                return
            }
            let result = Result(success: characteristic.value, failure: error)
            wrapper.didUpdate(data: result, forCharacteristic: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(characteristic: characteristic) else {
                return
            }
            let result = Result(success: characteristic.value, failure: error)
            wrapper.didWrite(data: result, forCharacteristic: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(characteristic: characteristic) else {
                return
            }
            let result = Result(success: characteristic.isNotifying, failure: error)
            wrapper.didUpdate(notificationState: result, forCharacteristic: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(characteristic: characteristic) else {
                return
            }
            let coreDescriptors = Result(success: characteristic.descriptors, failure: error)
            let shadowDescriptors = coreDescriptors.map { coreDescriptors in
                coreDescriptors.map {
                    ShadowDescriptor(core: $0, characteristic: wrapper)
                }
            }
            let descriptors = shadowDescriptors.map { shadowDescriptors -> [Descriptor] in
                shadowDescriptors.map { shadowDescriptor in
                    let descriptor = wrapper.makeDescriptor(shadow: shadowDescriptor)
                    wrapper.shadow.descriptors[shadowDescriptor.uuid] = descriptor
                    return descriptor
                }
            }
            wrapper.didDiscover(descriptors: descriptors, forCharacteristic: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(descriptor: descriptor) else {
                return
            }
            let result = Result(success: descriptor.value, failure: error)
            wrapper.didUpdate(any: result, forDescriptor: wrapper)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Swift.Error?) {
        //!  print("\(type(of: self)).\(#function)")
        self.queue.async {
            guard let wrapper = self.wrapperOf(descriptor: descriptor) else {
                return
            }
            let result = Result(success: descriptor.value, failure: error)
            wrapper.didWrite(any: result, forDescriptor: wrapper)
        }
    }
}

extension Result {

    init(success: T?, failure: E?) {
        switch (success, failure) {
        case (.some(let value), nil):
            self = .ok(value)
        case (nil, .some(let error)):
            self = .err(error)
        case (.some(_), .some(let error)):
            self = .err(error)
        case (nil, nil):
            fatalError("Result accepts either `success` or `failure` to be nil, not both")
        }
    }
}
