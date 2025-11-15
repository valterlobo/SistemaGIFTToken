// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title GiftToken
 * @dev Versão melhorada com correções de segurança da auditoria
 * @custom:security-contact security@gifttoken.io
 */
contract GiftToken is ERC20, AccessControl, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();
    error Unauthorized();
    error PoolAlreadyAuthorized();
    error PoolNotAuthorized();

    /*//////////////////////////////////////////////////////////////
                            ROLES
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Usar EnumerableSet para pools autorizados (mais seguro)
    EnumerableSet.AddressSet private authorizedPoolsSet;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PoolAuthorized(address indexed pool, uint256 timestamp);
    event PoolRevoked(address indexed pool, uint256 timestamp);
    event EmergencyPause(address indexed by, uint256 timestamp);
    event EmergencyUnpause(address indexed by, uint256 timestamp);
    event Minted(address indexed pool, address indexed to, uint256 amount);
    event Burned(address indexed pool, address indexed from, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory name, string memory symbol, address admin) ERC20(name, symbol) {
        if (admin == address(0)) revert ZeroAddress();

        // Admin tem todos os roles inicialmente
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POOL_MANAGER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                        POOL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adiciona um pool autorizado
     * @param pool Endereço do pool a ser autorizado
     */
    function addAuthorizedPool(address pool) external onlyRole(POOL_MANAGER_ROLE) {
        if (pool == address(0)) revert ZeroAddress();
        if (!authorizedPoolsSet.add(pool)) revert PoolAlreadyAuthorized();

        emit PoolAuthorized(pool, block.timestamp);
    }

    /**
     * @notice Remove um pool autorizado
     * @param pool Endereço do pool a ser removido
     */
    function removeAuthorizedPool(address pool) external onlyRole(POOL_MANAGER_ROLE) {
        if (!authorizedPoolsSet.remove(pool)) revert PoolNotAuthorized();

        emit PoolRevoked(pool, block.timestamp);
    }

    /**
     * @notice Verifica se um endereço é pool autorizado
     */
    function isAuthorizedPool(address pool) external view returns (bool) {
        return authorizedPoolsSet.contains(pool);
    }

    /**
     * @notice Retorna todos os pools autorizados
     */
    function getAllAuthorizedPools() external view returns (address[] memory) {
        return authorizedPoolsSet.values();
    }

    /**
     * @notice Retorna quantidade de pools autorizados
     */
    function getAuthorizedPoolCount() external view returns (uint256) {
        return authorizedPoolsSet.length();
    }

    /*//////////////////////////////////////////////////////////////
                        MINT/BURN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Cria novos tokens - apenas pools autorizados
     * @param to Endereço que receberá os tokens
     * @param amount Quantidade a ser criada
     */
    function mint(address to, uint256 amount) external whenNotPaused {
        if (!authorizedPoolsSet.contains(msg.sender)) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _mint(to, amount);

        emit Minted(msg.sender, to, amount);
    }

    /**
     * @notice Queima tokens - apenas pools autorizados
     * @param from Endereço de onde os tokens serão queimados
     * @param amount Quantidade a ser queimada
     */
    function burn(address from, uint256 amount) external whenNotPaused {
        if (!authorizedPoolsSet.contains(msg.sender)) revert Unauthorized();
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(from) < amount) revert InsufficientBalance();

        _burn(from, amount);

        emit Burned(msg.sender, from, amount);
    }

    /**
     * @notice Queima tokens direto do endereço (mais seguro para redeems)
     * @param from Endereço de onde queimar
     * @param amount Quantidade a queimar
     */
    function burnFrom(address from, uint256 amount) external whenNotPaused {
        if (!authorizedPoolsSet.contains(msg.sender)) revert Unauthorized();
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(from) < amount) revert InsufficientBalance();

        _burn(from, amount);

        emit Burned(msg.sender, from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pausa todas as operações de mint/burn/transfer
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    /**
     * @notice Despausa operações
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
        emit EmergencyUnpause(msg.sender, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Override para adicionar checagem de pause nas transferências
     */
    function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
        super._update(from, to, value);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Recupera tokens ERC20 enviados por engano
     * @dev Não permite recuperar o próprio GIFT token
     */
    function recoverERC20(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(this), "Cannot recover GIFT token");
        require(token != address(0), "Zero address");

        //IERC20(token).transfer(msg.sender, amount);
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}

