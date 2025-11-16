// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GiftToken} from "../src/GiftToken.sol";
import {GiftTokenFactory} from "../src/GiftTokenFactory.sol";

//import {ReservePool} from "../src/ReservePool.sol";

/**
 * @title Deploy
 * @dev Script para deploy do sistema completo GIFT Token
 *
 * Como usar:
 * forge script script/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --broadcast --verify
 */
contract Deploy is Script {
    // Endereços dos tokens de reserva (configurar para cada rede)
    address constant BR_TOKEN = address(0); // Substituir com endereço real
    address constant USDT_TOKEN = address(0); // Substituir com endereço real
    address constant HEAD_TOKEN = address(0); // Substituir com endereço real

    // Taxas de câmbio (com 18 decimais)
    uint256 constant BR_RATE = 10e18; // 1 BR = 10 GIFT
    uint256 constant USDT_RATE = 1e18; // 1 USDT = 1 GIFT
    uint256 constant HEAD_RATE = 0.2e18; // 1 HEAD = 0.2 GIFT

    // Valores mínimos
    uint256 constant MIN_BUY = 1e18;
    uint256 constant MIN_REDEEM = 1e18;

    // Merchants iniciais (configurar conforme necessário)
    address[] merchants;

    function setUp() public {
        // Adicionar merchants aqui
        // merchants.push(address(0x...));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying from:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy GIFT Token
        console.log("\n=== Deploying GIFT Token ===");
        GiftToken giftToken = new GiftToken("GIFT TOKEN", "GIFT", deployer);
        console.log("GIFT Token deployed at:", address(giftToken));

        // 2. Deploy Factory
        console.log("\n=== Deploying Factory ===");
        GiftTokenFactory factory = new GiftTokenFactory(address(giftToken));
        console.log("Factory deployed at:", address(factory));

        // 3. Criar Pools (apenas se os endereços dos tokens estiverem configurados)
        address brPool;
        address usdtPool;
        address headPool;

        if (BR_TOKEN != address(0)) {
            console.log("\n=== Creating BR Pool ===");
            brPool = factory.createReservePool(BR_TOKEN, BR_RATE, MIN_BUY, MIN_REDEEM);
            console.log("BR Pool created at:", brPool);

            // Adiciona merchants ao pool BR
            for (uint256 i = 0; i < merchants.length; i++) {
                factory.addMerchantToPool(brPool, merchants[i]);
                console.log("Added merchant:", merchants[i]);
            }
        }

        if (USDT_TOKEN != address(0)) {
            console.log("\n=== Creating USDT Pool ===");
            usdtPool = factory.createReservePool(USDT_TOKEN, USDT_RATE, MIN_BUY, MIN_REDEEM);
            console.log("USDT Pool created at:", usdtPool);

            // Adiciona merchants ao pool USDT
            for (uint256 i = 0; i < merchants.length; i++) {
                factory.addMerchantToPool(usdtPool, merchants[i]);
            }
        }

        if (HEAD_TOKEN != address(0)) {
            console.log("\n=== Creating HEAD Pool ===");
            headPool = factory.createReservePool(HEAD_TOKEN, HEAD_RATE, MIN_BUY, MIN_REDEEM);
            console.log("HEAD Pool created at:", headPool);

            // Adiciona merchants ao pool HEAD
            for (uint256 i = 0; i < merchants.length; i++) {
                factory.addMerchantToPool(headPool, merchants[i]);
            }
        }

        vm.stopBroadcast();

        // Log resumo
        console.log("\n=== Deployment Summary ===");
        console.log("GIFT Token:", address(giftToken));
        console.log("Factory:", address(factory));
        if (BR_TOKEN != address(0)) console.log("BR Pool:", brPool);
        if (USDT_TOKEN != address(0)) console.log("USDT Pool:", usdtPool);
        if (HEAD_TOKEN != address(0)) console.log("HEAD Pool:", headPool);

        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Add liquidity to pools using depositReserve()");
        console.log("3. Configure additional merchants if needed");
        console.log("4. Test buy and redeem operations");

        // Salva endereços em arquivo JSON
        string memory deployments = string(
            abi.encodePacked(
                "{\n",
                '  "giftToken": "',
                vm.toString(address(giftToken)),
                '",\n',
                '  "factory": "',
                vm.toString(address(factory)),
                '",\n',
                '  "brPool": "',
                vm.toString(brPool),
                '",\n',
                '  "usdtPool": "',
                vm.toString(usdtPool),
                '",\n',
                '  "headPool": "',
                vm.toString(headPool),
                '"\n',
                "}"
            )
        );

        vm.writeFile("deployments.json", deployments);
        console.log("\nDeployment addresses saved to deployments.json");
    }
}
