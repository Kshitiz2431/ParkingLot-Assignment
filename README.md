# Parking Lot System

A thread-safe parking lot management system implemented in Swift using modern concurrency features. The system handles multiple vehicle types, concurrent parking operations, and provides a command-line interface for interaction.

## Features

- **Concurrent Operations**: Thread-safe parking and unparking using Swift actors
- **Multiple Vehicle Types**: Supports bikes, cars, and trucks with different space requirements
- **Multi-Floor Support**: Manages multiple floors with configurable spots per floor
- **Real-time Status**: Track available spots and vehicle locations
- **Race Condition Handling**: Prevents duplicate parking and ensures data consistency
- **Command Line Interface**: Easy-to-use CLI for system interaction

## System Requirements

### Option 1: Local Development
- Swift 5.5 or later
- Xcode 13.0 or later (for development)
- macOS/Linux for running the application

### Option 2: Online Compiler
You can run this project directly in this online Swift compiler:
1. Visit [Swift Online Compiler](https://www.programiz.com/swift/online-compiler/)
2. Copy the entire code from `main.swift`
3. Paste into the online compiler
4. Click "Run" to execute the code

Note: This online compiler supports all features required for this project including Swift concurrency.

## Usage

The system provides the following commands:

1. `park <license_plate> <vehicle_type>` - Park a vehicle (types: car/bike/truck)
2. `remove <license_plate>` - Remove a vehicle
3. `status` - Show parking lot status
4. `find <license_plate>` - Find a vehicle
5. `test` - Run concurrent tests
6. `help` - Show help message
7. `exit` - Exit the program

### Example Usage:

```bash
Enter command:
park ABC123 car
> Vehicle parked successfully at floor 0, spot 1

Enter command:
status
> Floor 0: 4 spots available
> Floor 1: 5 spots available

Enter command:
find ABC123
> Vehicle found at floor 0, spot 1
```

## Design Features

### Concurrency Handling
- Uses Swift's actor model for thread safety
- Prevents race conditions in parking operations
- Ensures atomic updates to parking spot status

### Vehicle Management
- Different vehicle types require different numbers of spots
- Trucks require 2 consecutive spots
- Bikes and cars require 1 spot each

### Spot Allocation
- First-come-first-served basis
- Optimized spot search for multi-spot vehicles
- Maintains spot consistency across concurrent operations

## Testing

The system includes comprehensive tests for:
- Concurrent parking operations
- Race condition handling
- Performance testing
- Vehicle removal operations

Run tests using the `test` command in the CLI.

## Architecture

The system is built using several key components:

- `ParkingLot`: Main coordinator managing floors and vehicles
- `Floor`: Manages spots on individual floors
- `ParkingSpot`: Individual parking spot management
- `Vehicle`: Vehicle data model
- `ParkingLotCLI`: Command-line interface handler
