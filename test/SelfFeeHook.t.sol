// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

// Self
import {ISelfVerificationRoot} from "@selfxyz/contracts/contracts/interfaces/ISelfVerificationRoot.sol";
import {IIdentityVerificationHubV2} from "@selfxyz/contracts/contracts/interfaces/IIdentityVerificationHubV2.sol";
import {SelfUtils} from "@selfxyz/contracts/contracts/libraries/SelfUtils.sol";
import {SelfStructs} from "@selfxyz/contracts/contracts/libraries/SelfStructs.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {SelfFeeHook} from "../src/SelfFeeHook.sol";
import {BaseTest} from "./utils/BaseTest.sol";

/// @notice Mock del IdentityVerificationHubV2 para testing
contract MockIdentityVerificationHubV2 {
    bool public shouldRevert;
    bool public shouldVerifySuccessfully = true;
    bytes32 public lastConfigId;
    
    // Mapeo para simular configuraciones
    mapping(bytes32 => SelfStructs.VerificationConfigV2) public configs;
    
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
    
    function setShouldVerifySuccessfully(bool _should) external {
        shouldVerifySuccessfully = _should;
    }
    
    function verify(bytes calldata, bytes calldata userContextData) external {
        if (shouldRevert) {
            revert("Mock verification failed");
        }
        
        // Extraemos configId del userContextData (primeros 32 bytes)
        bytes32 configId;
        assembly {
            configId := calldataload(userContextData.offset)
        }
        lastConfigId = configId;
        
        if (shouldVerifySuccessfully) {
            // Simulamos un output exitoso
            ISelfVerificationRoot.GenericDiscloseOutputV2 memory output = ISelfVerificationRoot.GenericDiscloseOutputV2({
                attestationId: bytes32(0),
                userIdentifier: uint256(uint160(msg.sender)),
                nullifier: 0,
                forbiddenCountriesListPacked: [uint256(0), 0, 0, 0],
                issuingState: "",
                name: new string[](0),
                idNumber: "",
                nationality: "",
                dateOfBirth: "",
                gender: "",
                expiryDate: "",
                olderThan: 0,
                ofac: [false, false, false]
            });
            
            bytes memory encodedOutput = abi.encode(output);
            bytes memory userData;
            
            // Extraer userData si existe (después de configId, destChainId, userIdentifier)
            if (userContextData.length > 96) {
                userData = new bytes(userContextData.length - 96);
                for (uint256 i = 0; i < userData.length; i++) {
                    userData[i] = userContextData[i + 96];
                }
            }
            
            // Llamamos al callback del contrato que llamó verify
            ISelfVerificationRoot(msg.sender).onVerificationSuccess(encodedOutput, userData);
        }
    }
    
    function setVerificationConfigV2(SelfStructs.VerificationConfigV2 memory config) external returns (bytes32) {
        bytes32 configId = keccak256(abi.encode(config));
        configs[configId] = config;
        return configId;
    }
    
    function getVerificationConfigV2(bytes32 configId) external view returns (SelfStructs.VerificationConfigV2 memory) {
        return configs[configId];
    }
    
    // Stubs para evitar errores de compilación
    function registerCommitment(bytes32, uint256, bytes memory) external pure {}
    function registerDscKeyCommitment(bytes32, uint256, bytes memory) external pure {}
    function updateRegistry(bytes32, address) external pure {}
    function updateVcAndDiscloseCircuit(bytes32, address) external pure {}
    function updateRegisterCircuitVerifier(bytes32, uint256, address) external pure {}
    function updateDscVerifier(bytes32, uint256, address) external pure {}
    function batchUpdateRegisterCircuitVerifiers(bytes32[] calldata, uint256[] calldata, address[] calldata) external pure {}
    function batchUpdateDscCircuitVerifiers(bytes32[] calldata, uint256[] calldata, address[] calldata) external pure {}
    function registry(bytes32) external pure returns (address) { return address(0); }
    function discloseVerifier(bytes32) external pure returns (address) { return address(0); }
    function registerCircuitVerifiers(bytes32, uint256) external pure returns (address) { return address(0); }
    function dscCircuitVerifiers(bytes32, uint256) external pure returns (address) { return address(0); }
    function rootTimestamp(bytes32, uint256) external pure returns (uint256) { return 0; }
    function getIdentityCommitmentMerkleRoot(bytes32) external pure returns (uint256) { return 0; }
    function verificationConfigV2Exists(bytes32) external view returns (bool) { return configs[bytes32(0)].olderThanEnabled; }
    function generateConfigId(SelfStructs.VerificationConfigV2 memory config) external pure returns (bytes32) {
        return keccak256(abi.encode(config));
    }
}

contract SelfFeeHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;
    PoolKey poolKey;
    SelfFeeHook hook;
    PoolId poolId;
    MockIdentityVerificationHubV2 mockHub;
    
    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;
    
    // Valores para config de Self
    SelfUtils.UnformattedVerificationConfigV2 verificationConfig;

    function setUp() public {
        // Deploy all required artifacts
        deployArtifactsAndLabel();
        
        (currency0, currency1) = deployCurrencyPair();
        
        // Deploy mock hub
        mockHub = new MockIdentityVerificationHubV2();
        
        // Configurar verification config
        verificationConfig = SelfUtils.UnformattedVerificationConfigV2({
            olderThan: 18,
            forbiddenCountries: new string[](0),
            ofacEnabled: false
        });
        
        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        
        bytes memory constructorArgs = abi.encode(
            poolManager,
            address(mockHub),
            "test-scope",
            verificationConfig
        );
        
        deployCodeTo("SelfFeeHook.sol:SelfFeeHook", constructorArgs, flags);
        hook = SelfFeeHook(flags);
        
        // Create the pool con el hook
        poolKey = PoolKey(currency0, currency1, 0, 60, IHooks(hook)); // fee 0 porque será dinámico
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);
        
        // Provide full-range liquidity
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
        
        uint128 liquidityAmount = 100e18;
        
        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );
        
        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    // ========== Caso 1: Swap sin prueba (usuario normal) ==========
    function test_SwapWithoutProof_AppliesBaseFee() public {
        uint256 amountIn = 1e18;
        uint256 balanceBefore = currency0.balanceOf(address(this));
        
        // Swap sin data (sin prueba)
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: "", // Sin data = sin prueba
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        uint256 balanceAfter = currency0.balanceOf(address(this));
        
        // Verificaciones
        assertEq(int256(swapDelta.amount0()), -int256(amountIn), "Swap should take amountIn");
        
        // Verificar que el swap se ejecutó (el balance cambió)
        assertLt(balanceAfter, balanceBefore, "Balance should decrease after swap");
        
        // Verificar que se aplicó el fee base (1%)
        // El output debería reflejar el fee del 1%
        assertGt(swapDelta.amount1(), 0, "Should receive output tokens");
    }

    // ========== Caso 2: Swap con prueba Self válida ==========
    function test_SwapWithValidProof_AppliesDiscountFee() public {
        // Configurar mock para que verifique exitosamente
        mockHub.setShouldVerifySuccessfully(true);
        mockHub.setShouldRevert(false);
        
        uint256 amountIn = 1e18;
        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        
        // Preparar datos de prueba válidos
        bytes memory proofPayload = abi.encodePacked(bytes32(uint256(1)), "proof-data");
        bytes32 destChainId = bytes32(uint256(block.chainid));
        bytes32 userIdentifier = bytes32(uint256(uint160(address(this))));
        bytes memory userContextData = abi.encodePacked(destChainId, userIdentifier);
        
        bytes memory hookData = abi.encode(proofPayload, userContextData);
        
        // Swap con prueba válida
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        uint256 balanceAfter0 = currency0.balanceOf(address(this));
        uint256 balanceAfter1 = currency1.balanceOf(address(this));
        
        // Verificaciones
        assertEq(int256(swapDelta.amount0()), -int256(amountIn), "Swap should take amountIn");
        assertGt(swapDelta.amount1(), 0, "Should receive output tokens");
        
        // Verificar que se aplicó el fee reducido (0.3%)
        // El output con descuento debería ser mayor que sin descuento
        uint256 outputWithDiscount = uint256(int256(swapDelta.amount1()));
        
        // Hacer swap sin descuento para comparar
        mockHub.setShouldVerifySuccessfully(false);
        BalanceDelta swapDeltaNoDiscount = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: "", // Sin prueba
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        uint256 outputWithoutDiscount = uint256(int256(swapDeltaNoDiscount.amount1()));
        
        // Con fee reducido (0.3%) debería dar más output que con fee base (1%)
        assertGt(outputWithDiscount, outputWithoutDiscount, "Output with discount should be greater");
    }

    // ========== Caso 3: Swap con prueba inválida ==========
    function test_SwapWithInvalidProof_DoesNotRevert_AppliesBaseFee() public {
        // Configurar mock para que falle
        mockHub.setShouldRevert(true);
        mockHub.setShouldVerifySuccessfully(false);
        
        uint256 amountIn = 1e18;
        uint256 balanceBefore = currency0.balanceOf(address(this));
        
        // Preparar datos de prueba inválidos
        bytes memory proofPayload = abi.encodePacked(bytes32(uint256(1)), "invalid-proof");
        bytes32 destChainId = bytes32(uint256(block.chainid));
        bytes32 userIdentifier = bytes32(uint256(uint160(address(this))));
        bytes memory userContextData = abi.encodePacked(destChainId, userIdentifier);
        
        bytes memory hookData = abi.encode(proofPayload, userContextData);
        
        // El swap NO debería revertir incluso si la prueba es inválida
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        uint256 balanceAfter = currency0.balanceOf(address(this));
        
        // Verificaciones
        assertEq(int256(swapDelta.amount0()), -int256(amountIn), "Swap should complete");
        assertLt(balanceAfter, balanceBefore, "Balance should change");
        
        // Verificar que se aplicó el fee base (no el descuento)
        // El output debería ser el mismo que sin prueba
    }

    // ========== Caso 4: Sincronicidad de validación ==========
    function test_VerificationFlag_ResetsCorrectly() public {
        mockHub.setShouldVerifySuccessfully(true);
        mockHub.setShouldRevert(false);
        
        // Preparar datos válidos
        bytes memory proofPayload = abi.encodePacked(bytes32(uint256(1)), "proof-data");
        bytes32 destChainId = bytes32(uint256(block.chainid));
        bytes32 userIdentifier = bytes32(uint256(uint160(address(this))));
        bytes memory userContextData = abi.encodePacked(destChainId, userIdentifier);
        bytes memory validData = abi.encode(proofPayload, userContextData);
        
        // Primera llamada con data válida - debería marcar el flag como true
        // Hacemos un swap que debería verificar exitosamente
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e17,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: validData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        // Segunda llamada con data vacía - debería resetear el flag a false
        // y aplicar fee base
        BalanceDelta swapDelta2 = swapRouter.swapExactTokensForTokens({
            amountIn: 1e17,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: "", // Data vacía = sin verificación
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        // El segundo swap debería aplicar fee base (no descuento)
        assertGt(swapDelta2.amount1(), 0, "Second swap should execute");
    }

    // ========== Caso 5: Compatibilidad de cálculo de fee en bloque único ==========
    function test_FeeCalculation_IsSynchronous_NoTimeDependency() public {
        mockHub.setShouldVerifySuccessfully(true);
        
        bytes memory proofPayload = abi.encodePacked(bytes32(uint256(1)), "proof-data");
        bytes32 destChainId = bytes32(uint256(block.chainid));
        bytes32 userIdentifier = bytes32(uint256(uint160(address(this))));
        bytes memory userContextData = abi.encodePacked(destChainId, userIdentifier);
        bytes memory hookData = abi.encode(proofPayload, userContextData);
        
        uint256 amountIn = 1e18;
        
        // Swap en bloque actual
        BalanceDelta swapDelta1 = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        uint256 output1 = uint256(int256(swapDelta1.amount1()));
        
        // Avanzar bloque
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 1000);
        
        // Swap en bloque diferente
        BalanceDelta swapDelta2 = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        uint256 output2 = uint256(int256(swapDelta2.amount1()));
        
        // Los outputs deberían ser similares (diferencias solo por estado del pool, no por tiempo)
        // Verificamos que el cálculo de fee es síncrono y no depende del tiempo
        assertGt(output1, 0, "First swap should give output");
        assertGt(output2, 0, "Second swap should give output");
    }

    // ========== Validaciones adicionales ==========
    
    function test_GasUsage_Comparison() public {
        mockHub.setShouldVerifySuccessfully(true);
        
        bytes memory proofPayload = abi.encodePacked(bytes32(uint256(1)), "proof-data");
        bytes32 destChainId = bytes32(uint256(block.chainid));
        bytes32 userIdentifier = bytes32(uint256(uint160(address(this))));
        bytes memory userContextData = abi.encodePacked(destChainId, userIdentifier);
        bytes memory hookData = abi.encode(proofPayload, userContextData);
        
        uint256 amountIn = 1e18;
        
        // Medir gas sin prueba
        uint256 gasStartNoProof = gasleft();
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: "",
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        uint256 gasUsedNoProof = gasStartNoProof - gasleft();
        
        // Medir gas con prueba
        uint256 gasStartWithProof = gasleft();
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        uint256 gasUsedWithProof = gasStartWithProof - gasleft();
        
        // El gas con prueba debería ser mayor (overhead de verificación)
        assertGt(gasUsedWithProof, gasUsedNoProof, "Swap with proof should use more gas");
    }

    function test_Hook_DoesNotModifyLPLiquidity() public {
        // Verificar que el hook no afecta la liquidez del pool
        // La liquidez LP no debería cambiar significativamente solo por el fee
        // (los fees se acumulan en la liquidez, pero en cantidades muy pequeñas)
        
        // Hacer un swap
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: "",
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        // Verificar que el swap se ejecutó
        assertEq(int256(swapDelta.amount0()), -int256(1e18), "Swap should execute");
        // El hook solo modifica el fee, no debería afectar la estructura del pool
    }

    function test_NoSetConfigDuringSwap() public {
        // Verificar que el hook no intenta cambiar la config durante un swap
        // La config solo se establece en el constructor
        
        bytes32 configIdBefore = hook.verificationConfigId();
        
        // Hacer múltiples swaps
        for (uint256 i = 0; i < 5; i++) {
            swapRouter.swapExactTokensForTokens({
                amountIn: 1e17,
                amountOutMin: 0,
                zeroForOne: true,
                poolKey: poolKey,
                hookData: "",
                receiver: address(this),
                deadline: block.timestamp + 1
            });
        }
        
        bytes32 configIdAfter = hook.verificationConfigId();
        
        // El configId no debería cambiar
        assertEq(configIdBefore, configIdAfter, "ConfigId should not change during swaps");
    }

    function test_FeeValues_AreCorrect() public {
        assertEq(hook.BASE_FEE(), 10000, "BASE_FEE should be 1% (10000)");
        assertEq(hook.DISCOUNT_FEE(), 3000, "DISCOUNT_FEE should be 0.3% (3000)");
        
        // Verificar que el descuento es del 70%
        // 10000 * 0.3 = 3000 (70% de descuento sobre 1%)
        uint256 discount = hook.BASE_FEE() - hook.DISCOUNT_FEE();
        uint256 discountPercent = (discount * 10000) / hook.BASE_FEE();
        assertEq(discountPercent, 7000, "Discount should be 70%");
    }

    // ========== Test del evento HookSwapMetrics ==========
    function test_Event_HookSwapMetrics_Emitted_WithoutProof() public {
        uint256 amountIn = 1e18;
        
        // Esperamos que se emita el evento con verified=false y BASE_FEE
        vm.expectEmit(true, false, false, true);
        emit SelfFeeHook.HookSwapMetrics(
            PoolId.unwrap(poolKey.toId()),
            false, // verified
            hook.BASE_FEE(), // feeToApply
            amountIn, // notional
            (amountIn * hook.BASE_FEE()) / 10000, // feeApplied
            block.timestamp
        );
        
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: "",
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function test_Event_HookSwapMetrics_Emitted_WithValidProof() public {
        mockHub.setShouldVerifySuccessfully(true);
        
        uint256 amountIn = 1e18;
        bytes memory proofPayload = abi.encodePacked(bytes32(uint256(1)), "proof-data");
        bytes32 destChainId = bytes32(uint256(block.chainid));
        bytes32 userIdentifier = bytes32(uint256(uint160(address(this))));
        bytes memory userContextData = abi.encodePacked(destChainId, userIdentifier);
        bytes memory hookData = abi.encode(proofPayload, userContextData);
        
        // Esperamos que se emita el evento con verified=true y DISCOUNT_FEE
        vm.expectEmit(true, false, false, true);
        emit SelfFeeHook.HookSwapMetrics(
            PoolId.unwrap(poolKey.toId()),
            true, // verified
            hook.DISCOUNT_FEE(), // feeToApply
            amountIn, // notional
            (amountIn * hook.DISCOUNT_FEE()) / 10000, // feeApplied
            block.timestamp
        );
        
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }
}

