# Decentralized Stablecoin (DSC) Protocol

## Overview
The Decentralized Stablecoin (DSC) Protocol is a secure, over-collateralized stablecoin system implemented on Ethereum. It enables users to deposit crypto assets as collateral and mint stablecoins pegged to USD. The protocol ensures that the total supply of stablecoins never exceeds the total value of collateral, providing stability and reliability.

## Features
- **Mint Stablecoins:** Users can mint stablecoins by locking up collateral in supported crypto assets.
- **Redeem Collateral:** Users can redeem their collateral by burning stablecoins.
- **Over-Collateralization:** Ensures that the protocol is always sufficiently collateralized.
- **Invariant Testing:** Validates critical properties of the system, such as ensuring that the protocol's collateral value always exceeds the total stablecoin supply.
- **Fuzz Testing:** Simulates edge cases to ensure robustness against unexpected inputs.

## Smart Contracts
- **DSCEngine:** Core logic for handling collateral, minting, and redemption.
- **DecentralisedStableCoin:** The stablecoin token contract.
- **Handler:** Manages test scenarios for fuzz and invariant testing.

## Setup
### Prerequisites
- Foundry
- Node.js
- An Ethereum-compatible wallet (e.g., MetaMask)

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/dsc-protocol.git
   cd dsc-protocol
   ```
2. Install dependencies:
   ```bash
   forge install
   ```
3. Compile the contracts:
   ```bash
   forge build
   ```

## Foundry Commands
### Compilation
```bash
forge build
```
Compiles the smart contracts and generates ABI files.

### Running Tests
#### Unit Tests
```bash
forge test
```
Runs all unit tests to ensure the correctness of the protocol.

#### Fuzz Testing
```bash
forge test --fuzz-runner
```
Tests the protocol under randomized conditions.

#### Invariant Testing
```bash
forge test --match-contract Invariants
```
Ensures that the protocol invariants hold during all operations.

### Gas Report
```bash
forge test --gas-report
```
Generates a detailed gas usage report for each function.

## Contributing
Contributions are welcome! If you find bugs or have ideas for improvements, please open an issue or submit a pull request.

## License
This project is licensed under the MIT License.
