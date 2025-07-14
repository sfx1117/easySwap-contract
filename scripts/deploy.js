const { ethers, upgrades } = require("hardhat")

/**  * 2025/02/15 in sepolia testnet
 * esVault contract deployed to: 0xbBdA359F250761fA57C0fBeaF63c75Ba1A14767f
     esVault ImplementationAddress: 0x41D6e6CEDB6748FeC02063Ed85c90fe59E4FCFcc
     esVault AdminAddress: 0xcDb8c3ad532eA641cFb1862D332E3238a164210b
   esDex contract deployed to: 0x827B2Eb914d2AaB14CA3C735dF0D73A220E59F3F
      esDex ImplementationAddress: 0xE876947d22AAD704e1aEA0297D58092666551e0b
      esDex AdminAddress: 0xcDb8c3ad532eA641cFb1862D332E3238a164210b
 */

async function main() {
  const [deployer] = await ethers.getSigners()
  console.log("deployer: ", deployer.address)

  // let esVault = await ethers.getContractFactory("EasySwapVault")
  // esVault = await upgrades.deployProxy(esVault, { initializer: 'initialize' });
  // await esVault.deployed()
  // console.log("esVault contract deployed to:", esVault.address)
  // console.log(await upgrades.erc1967.getImplementationAddress(esVault.address), " esVault getImplementationAddress")
  // console.log(await upgrades.erc1967.getAdminAddress(esVault.address), " esVault getAdminAddress")

  // newProtocolShare = 200;
  // newESVault = "0xbBdA359F250761fA57C0fBeaF63c75Ba1A14767f";
  // EIP712Name = "EasySwapOrderBook";
  // EIP712Version = "1";
  // let esDex = await ethers.getContractFactory("EasySwapOrderBook")
  // esDex = await upgrades.deployProxy(esDex, [newProtocolShare, newESVault, EIP712Name, EIP712Version], { initializer: 'initialize' });
  // await esDex.deployed()
  // console.log("esDex contract deployed to:", esDex.address)
  // console.log(await upgrades.erc1967.getImplementationAddress(esDex.address), " esDex getImplementationAddress")
  // console.log(await upgrades.erc1967.getAdminAddress(esDex.address), " esDex getAdminAddress")

  esDexAddress = "0x827B2Eb914d2AaB14CA3C735dF0D73A220E59F3F"
  esVaultAddress = "0xbBdA359F250761fA57C0fBeaF63c75Ba1A14767f"
  const esVault = await (
    await ethers.getContractFactory("EasySwapVault")
  ).attach(esVaultAddress)
  tx = await esVault.setOrderBook(esDexAddress)
  await tx.wait()
  console.log("esVault setOrderBook tx:", tx.hash)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
