// Importuj wymagane moduły
const { ethers } = require("ethers");
const fs = require("fs-extra");

async function main() {
  // Adres kontraktu Vault
  // const vaultAddress = "0xebb37b957f97661949c308c80d4b4ed21c26dd8c"; // Zmień na rzeczywisty adres
  const vaultAddress = "0x41505Ed902611E0b21375E8f8E6E27060CD96E06";

  // ABI kontraktu Vault (zawierające metodę withdrawAllTokensAndETH)
  const vaultABI = [
    "function withdrawAllTokensAndETH(address[] tokens) external",
  ];

  // Adres tokenów, które mają być wypłacone
  // const tokens = [
  //   "0x0723dfdb59072ffde155da561312dbc0da8bd31b", // Zmień na rzeczywiste adresy tokenów
  //   "0x2e659c2b976830da6f3168d1f23250bf2e86e845",
  //   "0xec1346242af7f200d311a3d8298c5c1f692ffd06",
  // ];

  const tokens = [
    "0x04E45E666d62e826c489f285aE0CD68127EC301d",
    "0x3eD054785a47Ec804FfBe759E851e189916EBcfb",
  ];

  // Podłącz się do sieci Ethereum
  const provider = new ethers.JsonRpcProvider(
    "https://evm-rpc-arctic-1.sei-apis.com"
  );

  // Uzyskaj portfel właściciela kontraktu
  const privateKey =
    "30834115a8e07ad4ebbd954391c34acd8a25d54bcdec68c1442108da99359450"; // Zmień na rzeczywisty klucz prywatny właściciela, przechowuj w zmiennej środowiskowej
  if (!privateKey) {
    throw new Error(
      "Brak klucza prywatnego. Ustaw PRIVATE_KEY w zmiennych środowiskowych."
    );
  }
  const wallet = new ethers.Wallet(privateKey, provider);

  // Stwórz instancję kontraktu Vault
  const vaultContract = new ethers.Contract(vaultAddress, vaultABI, wallet);
  console.log({ vaultContract });

  try {
    console.log("Wywoływanie funkcji withdrawAllTokensAndETH...");

    // Wywołaj funkcję withdrawAllTokensAndETH
    const tx = await vaultContract.withdrawAllTokensAndETH(tokens);

    console.log("Transakcja wysłana. Oczekiwanie na potwierdzenie...");
    const receipt = await tx.wait();

    console.log("Transakcja potwierdzona! Szczegóły:", receipt);
  } catch (error) {
    console.error("Błąd podczas wywoływania funkcji:", error);
  }
}

// Uruchom skrypt
main().catch((error) => {
  console.error("Błąd główny:", error);
  process.exit(1);
});
