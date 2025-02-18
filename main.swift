import Foundation

struct ParkingTestResult {
    let licensePlate: String
    let success: Bool
    let error: Error?
}

func runConcurrentTests(parkingLot: ParkingLot) async {
    print("\n=== Starting Concurrent Parking Tests ===\n")
    
    
    let testVehicles = [
        ("TRUCK1", VehicleType.truck),  // Should take 2 spots
        ("CAR001", VehicleType.car),
        ("BIKE01", VehicleType.bike),
        ("TRUCK2", VehicleType.truck),  // Should take 2 spots
        ("CAR002", VehicleType.car),
        ("BIKE02", VehicleType.bike)
    ]
    
    var results: [ParkingTestResult] = []
    
    print("Sending \(testVehicles.count) concurrent parking requests...")
    print("Note: Trucks require 2 consecutive spots\n")
    
    // Executing all parking requests concurrently
    await withTaskGroup(of: ParkingTestResult.self) { group in
        for (plate, type) in testVehicles {
            group.addTask {
                do {
                    let location = try await parkingLot.parkVehicle(plate, type: type)
                    print("Successfully parked \(plate) (\(type)) at floor \(location.floor), spot \(location.spot)")
                    return ParkingTestResult(licensePlate: plate, success: true, error: nil)
                } catch {
                    print("Failed to park \(plate) (\(type)): \(error)")
                    return ParkingTestResult(licensePlate: plate, success: false, error: error)
                }
            }
        }
        
        for await result in group {
            results.append(result)
        }
    }
    
    print("\n=== Test Results ===")
    print("Total vehicles: \(testVehicles.count)")
    print("Successfully parked: \(results.filter { $0.success }.count)")
    print("Failed to park: \(results.filter { !$0.success }.count)")
    
    print("\nParking lot status:")
    let spots = await parkingLot.getAvailableSpotsPerFloor()
    for (floor, available) in spots {
        print("Floor \(floor): \(available) spots available")
    }
    
    // Testing concurrent vehicle removal
    print("\n=== Testing Concurrent Vehicle Removal ===")
    
    await withTaskGroup(of: Bool.self) { group in
        for result in results where result.success {
            group.addTask {
                do {
                    try await parkingLot.removeVehicle(result.licensePlate)
                    print("Successfully removed \(result.licensePlate)")
                    return true
                } catch {
                    print("Failed to remove \(result.licensePlate): \(error)")
                    return false
                }
            }
        }
        
        for await _ in group { }
    }
    
    print("\nFinal parking lot status:")
    let finalSpots = await parkingLot.getAvailableSpotsPerFloor()
    for (floor, available) in finalSpots {
        print("Floor \(floor): \(available) spots available")
    }
}

func testRaceConditions(parkingLot: ParkingLot) async {
    print("\n=== Testing Race Conditions ===\n")
    
    // Trying to park same vehicle from multiple tasks
    await withTaskGroup(of: Bool.self) { group in
        for i in 1...5 {
            group.addTask {
                do {
                    let _ = try await parkingLot.parkVehicle("TEST-CAR", type: .car)
                    print("Task \(i): Successfully parked TEST-CAR")
                    return true
                } catch {
                    print("Task \(i): Failed to park TEST-CAR - \(error)")
                    return false
                }
            }
        }
        
        for await _ in group { }
    }
}

func testParkingPerformance(parkingLot: ParkingLot) async {
    print("\n=== Testing Parking Performance ===\n")
    
    let numOperations = 50
    
    print("Starting \(numOperations) concurrent parking operations...")
    
    let startTime = DispatchTime.now()
    var successCount = 0
    
    await withTaskGroup(of: Bool.self) { group in
        for i in 1...numOperations {
            group.addTask {
                do {
                    let _ = try await parkingLot.parkVehicle("VEH-\(i)", type: .car)
                    return true
                } catch {
                    return false
                }
            }
        }
        
        for await result in group {
            if result {
                successCount += 1
            }
        }
    }
    
    let endTime = DispatchTime.now()
    let nanoTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
    let timeInterval = Double(nanoTime) / 1_000_000_000 // Convert to seconds
    
    print("\nPerformance Results:")
    print("Total operations attempted: \(numOperations)")
    print("Successful operations: \(successCount)")
    print("Failed operations: \(numOperations - successCount)")
    print("Total time elapsed: \(String(format: "%.3f", timeInterval)) seconds")
    print("Average time per operation: \(String(format: "%.4f", timeInterval/Double(numOperations))) seconds")
}


func runAllTests(parkingLot: ParkingLot) async {
    await runConcurrentTests(parkingLot: parkingLot)
    await testRaceConditions(parkingLot: parkingLot)
    await testParkingPerformance(parkingLot: parkingLot)
}

enum VehicleType {
    case bike
    case car
    case truck
    
    var requiredSpots: Int {
        switch self {
        case .bike, .car: return 1
        case .truck: return 2
        }
    }
}

struct Vehicle {
    let licensePlate: String
    let type: VehicleType
}

actor ParkingSpot {
    let floor: Int
    let spotNumber: Int
    private(set) var isOccupied: Bool
    private(set) var vehicle: Vehicle?
    
    init(floor: Int, spotNumber: Int) {
        self.floor = floor
        self.spotNumber = spotNumber
        self.isOccupied = false
        self.vehicle = nil
    }
    
    func occupy(with vehicle: Vehicle) {
        self.vehicle = vehicle
        self.isOccupied = true
    }
    
    func vacate() {
        self.vehicle = nil
        self.isOccupied = false
    }
}


enum ParkingLotError: Error {
    case vehicleAlreadyParked
    case parkingFull
    case vehicleNotFound
    case invalidOperation
}


actor Floor {
    let floorNumber: Int
    private(set) var spots: [ParkingSpot]
    private var spotAllocationMap: [Int: Bool]
    
    init(floorNumber: Int, totalSpots: Int) {
        self.floorNumber = floorNumber
        self.spots = (0..<totalSpots).map { ParkingSpot(floor: floorNumber, spotNumber: $0) }
        self.spotAllocationMap = Dictionary(uniqueKeysWithValues: (0..<totalSpots).map { ($0, false) })
    }
    
    var availableSpots: Int {
        get async {
            spotAllocationMap.filter { !$0.value }.count
        }
    }
    
    func findAvailableSpots(count: Int) async -> [ParkingSpot]? {
        var consecutiveSpots: [ParkingSpot] = []
        var consecutiveIndices: [Int] = []
        
        for (index, spot) in spots.enumerated() {
            if !spotAllocationMap[index, default: true] {
                consecutiveSpots.append(spot)
                consecutiveIndices.append(index)
                
                if consecutiveSpots.count == count {
                    for idx in consecutiveIndices {
                        spotAllocationMap[idx] = true
                    }
                    print("Reserved spots \(consecutiveIndices) on floor \(floorNumber)")
                    return consecutiveSpots
                }
            } else {
                consecutiveSpots.removeAll()
                consecutiveIndices.removeAll()
            }
        }
        
        return nil
    }
    
    func getSpot(_ spotNumber: Int) async -> ParkingSpot? {
        return spots.first { $0.spotNumber == spotNumber }
    }
    
    func markSpotAsAvailable(_ spotNumber: Int) async {
        spotAllocationMap[spotNumber] = false
        if let spot = await getSpot(spotNumber) {
            await spot.vacate()
        }
    }
}


actor ParkingLot {
    private var floors: [Floor]
    private var vehicleLocations: [String: [Int: [Int]]]  // [licensePlate: [floor: [spots]]]
    private var parkedVehicles: [String: Vehicle]  // For double-checking vehicle uniqueness
    
    init(numFloors: Int, spotsPerFloor: Int) {
        self.floors = (0..<numFloors).map { Floor(floorNumber: $0, totalSpots: spotsPerFloor) }
        self.vehicleLocations = [:]
        self.parkedVehicles = [:]
    }
    
    func parkVehicle(_ licensePlate: String, type: VehicleType) async throws -> (floor: Int, spot: Int) {
        // First check if vehicle is already parked - this needs to be atomic
        if parkedVehicles[licensePlate] != nil {
            throw ParkingLotError.vehicleAlreadyParked
        }
        
        let vehicle = Vehicle(licensePlate: licensePlate, type: type)
        let requiredSpots = type.requiredSpots
        
        // Find nearest available spots
        for floor in floors {
            if let availableSpots = await floor.findAvailableSpots(count: requiredSpots) {
                // Before occupying spots, check again if vehicle was parked
                // during our search for spots
                if parkedVehicles[licensePlate] != nil {
                    // Release the spots we found
                    for spot in availableSpots {
                        await floor.markSpotAsAvailable(spot.spotNumber)
                    }
                    throw ParkingLotError.vehicleAlreadyParked
                }
                
                for spot in availableSpots {
                    await spot.occupy(with: vehicle)
                }
                
                vehicleLocations[licensePlate] = [floor.floorNumber: availableSpots.map { $0.spotNumber }]
                parkedVehicles[licensePlate] = vehicle
                
                return (floor: floor.floorNumber, spot: availableSpots[0].spotNumber)
            }
        }
        
        throw ParkingLotError.parkingFull
    }
    
    func removeVehicle(_ licensePlate: String) async throws {
        guard let locationMap = vehicleLocations[licensePlate],
              let (floorNum, spotNums) = locationMap.first else {
            throw ParkingLotError.vehicleNotFound
        }
        
        guard let floor = floors.first(where: { $0.floorNumber == floorNum }) else {
            throw ParkingLotError.invalidOperation
        }
        
        // Vacate all spots
        for spotNum in spotNums {
            await floor.markSpotAsAvailable(spotNum)
        }
        
        // Remove records atomically
        vehicleLocations.removeValue(forKey: licensePlate)
        parkedVehicles.removeValue(forKey: licensePlate)
    }
    
    func getVehicleLocation(_ licensePlate: String) -> (floor: Int, spot: Int)? {
        if let locationMap = vehicleLocations[licensePlate],
           let (floor, spots) = locationMap.first,
           let firstSpot = spots.first {
            return (floor: floor, spot: firstSpot)
        }
        return nil
    }
    
    func getParkedVehicle(_ licensePlate: String) async -> Vehicle? {
        return parkedVehicles[licensePlate]
    }
    
    func getAvailableSpotsPerFloor() async -> [Int: Int] {
        var spotsAvailable: [Int: Int] = [:]
        for floor in floors {
            spotsAvailable[floor.floorNumber] = await floor.availableSpots
        }
        return spotsAvailable
    }
    
    var isFull: Bool {
        get async {
            for floor in floors {
                if await floor.availableSpots > 0 {
                    return false
                }
            }
            return true
        }
    }
}

// Command Line Interface

enum Command: String {
    case park = "park"
    case remove = "remove"
    case status = "status"
    case find = "find"
    case help = "help"
    case test = "test"
    case exit = "exit"
    
    static func showHelp() {
        print("""
        Available commands:
        1. park <license_plate> <vehicle_type>   - Park a vehicle (type: car/bike/truck)
        2. remove <license_plate>                - Remove a vehicle
        3. status                               - Show parking lot status
        4. find <license_plate>                 - Find a vehicle
        5. test                                 - Run concurrent tests
        6. exit                                 - Exit the program
        """)
    }
}

@MainActor
class ParkingLotCLI {
    private let parkingLot: ParkingLot
    
    init(numFloors: Int, spotsPerFloor: Int) {
        self.parkingLot = ParkingLot(numFloors: numFloors, spotsPerFloor: spotsPerFloor)
        print("Created parking lot with \(numFloors) floors and \(spotsPerFloor) spots per floor")
    }
    
    func processCommand(_ input: String) async -> Bool {
        let components = input.split(separator: " ").map(String.init)
        guard let commandString = components.first,
              let command = Command(rawValue: commandString.lowercased()) else {
            print("Invalid command. Type 'help' for available commands.")
            return true
        }
        
        do {
            switch command {
            case .park:
                guard components.count == 3 else {
                    print("Usage: park <license_plate> <vehicle_type>")
                    return true
                }
                let licensePlate = components[1]
                guard let vehicleType = parseVehicleType(components[2]) else {
                    print("Invalid vehicle type. Use: car, bike, or truck")
                    return true
                }
                
                let location = try await parkingLot.parkVehicle(licensePlate, type: vehicleType)
                print("Vehicle parked successfully at floor \(location.floor), spot \(location.spot)")
                
            case .remove:
                guard components.count == 2 else {
                    print("Usage: remove <license_plate>")
                    return true
                }
                try await parkingLot.removeVehicle(components[1])
                print("Vehicle removed successfully")
                
            case .status:
                let spots = await parkingLot.getAvailableSpotsPerFloor()
                print("\nParking Lot Status:")
                print("-------------------")
                for (floor, available) in spots {
                    print("Floor \(floor): \(available) spots available")
                }
                print("Parking lot is \(await parkingLot.isFull ? "full" : "not full")")
                
            case .find:
                guard components.count == 2 else {
                    print("Usage: find <license_plate>")
                    return true
                }
                if let location = await parkingLot.getVehicleLocation(components[1]) {
                    print("Vehicle found at floor \(location.floor), spot \(location.spot)")
                } else {
                    print("Vehicle not found in parking lot")
                }
                
            case .help:
                Command.showHelp()
                
            case .test:
                await runAllTests(parkingLot: parkingLot)
                
            case .exit:
                print("Goodbye!")
                return false
            }
        } catch ParkingLotError.vehicleAlreadyParked {
            print("Error: Vehicle is already parked")
        } catch ParkingLotError.parkingFull {
            print("Error: Parking lot is full")
        } catch ParkingLotError.vehicleNotFound {
            print("Error: Vehicle not found")
        } catch {
            print("Error: \(error)")
        }
        
        return true
    }
    
    private func parseVehicleType(_ type: String) -> VehicleType? {
        switch type.lowercased() {
        case "car": return .car
        case "bike": return .bike
        case "truck": return .truck
        default: return nil
        }
    }
    
    func run() async {
        print("\nWelcome to Parking Lot System")
        print("Type 'help' for available commands")
        
        while true {
            print("\nEnter command:")
            guard let input = readLine(), !input.isEmpty else {
                continue
            }
            
            if !(await processCommand(input)) {
                break
            }
        }
    }
}

//  Main Program

func mainAsync() async {
    print("Initialize Parking Lot")
    print("Enter number of floors:")
    guard let floorsInput = readLine(),
          let numFloors = Int(floorsInput) else {
        print("Invalid input for number of floors")
        return
    }
    
    print("Enter spots per floor:")
    guard let spotsInput = readLine(),
          let spotsPerFloor = Int(spotsInput) else {
        print("Invalid input for spots per floor")
        return
    }
    
    let cli = await ParkingLotCLI(numFloors: numFloors, spotsPerFloor: spotsPerFloor)
    await cli.run()
}

await mainAsync()
