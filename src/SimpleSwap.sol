// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SimpleSwap
 * @notice 테스트용 간단한 스왑 컨트랙트
 * - createPair: 스왑 가능한 토큰 쌍을 생성 (양방향)
 * - depositLiquidity: 유동성 제공 (토큰을 컨트랙트에 예치)
 * - swap: 1:1 고정 환율로 스왑 실행 (토큰 in과 토큰 out의 쌍이 미리 생성되어 있어야 함)
 */
contract SimpleSwap {
    // 두 토큰간 스왑 쌍 정보를 저장합니다.
    mapping(address => mapping(address => bool)) public hasPair;

    event PairCreated(address indexed tokenA, address indexed tokenB);
    event LiquidityDeposited(address indexed token, address indexed provider, uint256 amount);
    event Swapped(
        address indexed swapper, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /**
     * @notice 두 토큰간 스왑 쌍을 생성합니다.
     * @param tokenA 첫 번째 토큰 주소
     * @param tokenB 두 번째 토큰 주소
     */
    function createPair(address tokenA, address tokenB) external {
        require(tokenA != tokenB, "Tokens must be different");
        require(!hasPair[tokenA][tokenB], "Pair already exists");
        // 양방향으로 허용
        hasPair[tokenA][tokenB] = true;
        hasPair[tokenB][tokenA] = true;
        emit PairCreated(tokenA, tokenB);
    }

    /**
     * @notice 유동성 공급자가 컨트랙트에 토큰을 예치합니다.
     * @param token 예치할 토큰 주소
     * @param amount 예치할 토큰 수량
     *
     * 주의: 토큰의 transferFrom을 위해 사전에 approve가 필요합니다.
     */
    function depositLiquidity(address token, uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit LiquidityDeposited(token, msg.sender, amount);
    }

    /**
     * @notice 스왑을 실행합니다.
     * @param tokenIn 스왑할 때 입력 토큰 주소
     * @param tokenOut 스왑할 때 받을 토큰 주소
     * @param amountIn 입력 토큰 수량
     * @param minAmountOut 최소 수령 토큰 수량 (슬리피지 보호용)
     *
     * 테스트용으로 1:1 고정 환율로 스왑됩니다.
     * 주의: 입력 토큰의 transferFrom을 위해 사전에 approve가 필요하며,
     * 컨트랙트가 tokenOut의 충분한 유동성을 보유하고 있어야 합니다.
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut) external {
        require(hasPair[tokenIn][tokenOut], "Swap pair not available");
        require(amountIn > 0, "Amount must be > 0");

        // 테스트 용도로 1:1 환율로 스왑 처리 (실제에서는 가격 산정 로직 필요)
        uint256 amountOut = amountIn;
        require(amountOut >= minAmountOut, "Output amount less than minimum required");

        // 입력 토큰을 사용자로부터 컨트랙트로 전송
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "Transfer of tokenIn failed");

        // 컨트랙트가 보유한 토큰 out 잔액 확인
        uint256 liquidity = IERC20(tokenOut).balanceOf(address(this));
        require(liquidity >= amountOut, "Insufficient liquidity for tokenOut");

        // 컨트랙트로부터 사용자에게 토큰 out 전송
        require(IERC20(tokenOut).transfer(msg.sender, amountOut), "Transfer of tokenOut failed");

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }
}
