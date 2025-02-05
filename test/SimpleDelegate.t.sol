// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MyERC20} from "src/MyERC20.sol";
import {SimpleDelegate} from "src/SimpleDelegate.sol";
import {SafeSimpleDelegate} from "src/SafeSimpleDelegate.sol";
import {SimpleSwap} from "src/SimpleSwap.sol";

/**
 * @title SimpleDelegateTest
 * @notice 이 테스트 계약은 delegation을 이용한 호출 실행 방식의 취약점(unsafe)과
 *         개선된 안전 방식(safe)을 검증하기 위한 테스트 시나리오들을 포함합니다.
 *
 * 전체 테스트는 다음과 같은 시나리오를 다룹니다:
 * 1. 단순 ERC20 approve를 통한 토큰 스왑 진행
 * 2. Approval 없이 스왑 호출 시도 시 실패하는 경우
 * 3. Unsafe delegation을 이용해 ALICE의 권한을 도용, BOB가 ALICE의 토큰을 swap 계약을 통해 스왑.
 * 4. Unsafe delegation을 악의적으로 활용하여 ALICE의 잔액 전체를 BOB로 전송하는 경우
 * 5. Safe delegation을 통해 오직 ALICE만이 자신의 토큰 전송 호출을 실행하는 경우
 * 6. ALICE가 아닌 다른 계정(Bob)이 safe delegation을 사용하여 호출하면 revert되는 경우
 *
 * 주의: unsafe delegation은 누구나 ALICE의 delegate 코드를 사용할 수 있다는 점에서 큰 보안 취약점을 내포합니다.
 */
contract SimpleDelegateTest is Test {
    // 토큰 관련 상수: mint 및 swap에 사용
    uint256 constant MINT_AMOUNT = 1000 ether;
    uint256 constant SWAP_AMOUNT = 100 ether;

    uint256 ALICE_PVK;
    uint256 BOB_PVK;

    address ALICE;
    address BOB;

    // 테스트에서 사용할 계약 인스턴스들
    SimpleDelegate public unsafeImplementation; // 누구나 호출할 수 있는 unsafe delegation 구현
    SafeSimpleDelegate public safeImplementation; // 오직 소유자 자신만 호출할 수 있는 safe delegation 구현
    SimpleSwap public swap; // 스왑 기능을 제공하는 계약
    MyERC20 public usdc; // 테스트용 USDC 토큰 (6자리 소수점)
    MyERC20 public usdk; // 테스트용 USDK 토큰 (6자리 소수점)

    /**
     * @notice 테스트 환경 초기화 함수.
     * @dev 테스트 환경 구성:
     *  - ALICE와 BOB의 주소와 개인키를 생성합니다. (vm.makeAddrAndKey 사용)
     *  - Unsafe delegation과 Safe delegation을 위한 구현 계약을 배포합니다.
     *  - ERC20 토큰 USDC와 USDK를 생성하고, 각각 ALICE와 swap 계약에 일정량(MINT_AMOUNT)을 할당합니다.
     *  - swap 계약 배포 후 USDC-USDK 토큰 쌍(pair)를 생성 및 확인합니다.
     */
    function setUp() public {
        // ALICE와 BOB의 주소 및 개인키 생성
        (ALICE, ALICE_PVK) = makeAddrAndKey("ALICE");
        (BOB, BOB_PVK) = makeAddrAndKey("BOB");

        // Unsafe delegation 구현 계약 배포: 누구나 execute를 호출할 수 있어 보안상 위험합니다.
        unsafeImplementation = new SimpleDelegate();
        // Safe delegation 구현 계약 배포: 계정 소유자(예, ALICE)만 호출 가능하도록 제한되어 있습니다.
        safeImplementation = new SafeSimpleDelegate();

        // USDC와 USDK 토큰 생성 (각각 6자리 소수점 지원)
        usdc = new MyERC20("USDC", "USDC", 6);
        usdk = new MyERC20("USDK", "USDK", 6);

        // 스왑 계약 배포 및 USDC-USDK 토큰 쌍(pair) 생성
        swap = new SimpleSwap();
        swap.createPair(address(usdc), address(usdk));

        // 생성된 토큰 쌍(pair)이 올바르게 등록되었는지 확인
        assertTrue(swap.hasPair(address(usdc), address(usdk)));
        assertTrue(swap.hasPair(address(usdk), address(usdc)));

        // 토큰 발행:
        // - ALICE에게 USDC를 MINT_AMOUNT만큼 할당합니다.
        // - swap 계약에는 USDK를 MINT_AMOUNT만큼 할당합니다.
        usdc.mint(ALICE, MINT_AMOUNT);
        usdk.mint(address(swap), MINT_AMOUNT);

        // 초기 토큰 잔액이 예상대로 할당되었는지 확인합니다.
        assertEq(usdc.balanceOf(ALICE), MINT_AMOUNT);
        assertEq(usdk.balanceOf(address(swap)), MINT_AMOUNT);
    }

    /**
     * @notice 시나리오: ALICE가 직접 ERC20 approve 후 swap 계약을 통해 토큰 스왑을 실행하는 과정.
     * @dev 수행 단계:
     *  1. ALICE 역할로 실행 컨텍스트(vm.startPrank)를 시작합니다.
     *  2. ALICE가 swap 계약에 대해 SWAP_AMOUNT만큼 USDC 전송 권한을 approve 합니다.
     *  3. swap.swap 함수를 호출해 USDC를 USDK로 교환 (여기서는 1:1 스왑)합니다.
     *  4. 최종적으로 ALICE와 swap의 각 토큰 잔액이 올바르게 변했음을 확인합니다.
     */
    function test_SwapWithApproval() public {
        // ALICE의 컨텍스트로 실행 시작
        vm.startPrank(ALICE);

        // ALICE가 swap 계약에 대해 자신의 USDC 토큰 SWAP_AMOUNT 승인
        usdc.approve(address(swap), SWAP_AMOUNT);

        // swap 계약 호출: ALICE의 USDC를 USDK로 스왑 (1:1 비율)
        swap.swap(address(usdc), address(usdk), SWAP_AMOUNT, SWAP_AMOUNT);

        // ALICE 컨텍스트 종료
        vm.stopPrank();

        // 교환 후 결과 검증:
        // - ALICE의 USDC 잔액: MINT_AMOUNT에서 SWAP_AMOUNT 만큼 차감됨.
        // - ALICE의 USDK 잔액: SWAP_AMOUNT만큼 증가됨.
        // - swap 계약의 USDC 잔액: SWAP_AMOUNT만큼 증가됨.
        // - swap 계약의 USDK 잔액: MINT_AMOUNT에서 SWAP_AMOUNT 만큼 차감됨.
        assertEq(usdc.balanceOf(ALICE), MINT_AMOUNT - SWAP_AMOUNT);
        assertEq(usdk.balanceOf(ALICE), SWAP_AMOUNT);
        assertEq(usdc.balanceOf(address(swap)), SWAP_AMOUNT);
        assertEq(usdk.balanceOf(address(swap)), MINT_AMOUNT - SWAP_AMOUNT);
    }

    /**
     * @notice 시나리오: ALICE가 미승인 상태에서 swap 계약 호출 시도 시, 스왑이 실패(revert)하는지 검증.
     * @dev 수행 단계:
     *  1. ALICE가 approve 없이 swap.swap 함수를 호출합니다.
     *  2. 트랜잭션 실행 시 ERC20 토큰의 전송이 승인되지 않아 revert되어야 함을 검증합니다.
     */
    function test_Revert_SwapWithoutApproval() public {
        // 승인 없이 swap 호출 시 반드시 revert가 발생해야 하므로, vm.expectRevert 사용
        vm.expectRevert();

        // ALICE 컨텍스트로 실행: approve 없이 swap.swap 호출 -> 실패 예상
        vm.prank(ALICE);
        swap.swap(address(usdc), address(usdk), SWAP_AMOUNT, SWAP_AMOUNT);
    }

    /**
     * @notice 시나리오: Unsafe delegation을 이용해 ALICE의 권한을 도용, BOB가 ALICE의 토큰을 swap 계약을 통해 스왑.
     * @dev 수행 단계:
     *  1. ALICE는 자신의 개인키를 사용하여 unsafe delegation 서명을 생성하고, 이를 통해 자신의 계정에 delegation 코드를 부착합니다.
     *     - 부착된 코드 존재 여부를 ALICE 계정의 코드 길이로 확인합니다.
     *  2. BOB는 두 개의 호출(Call) 배열을 준비합니다.
     *     - Call 1: ALICE 계정의 usdc 토큰에서 swap 계약에 대해 SWAP_AMOUNT 승인.
     *     - Call 2: swap.swap 함수 호출하여 USDC를 USDK로 스왑.
     *  3. BOB는 ALICE에 부착된 unsafe delegation의 execute 함수를 호출하여 위 호출들을 실행합니다.
     *  4. 최종적으로 ALICE와 swap 계약의 토큰 잔액이 예상대로 변경되었음을 확인합니다.
     *
     * 주의: Unsafe delegation은 모든 외부 사용자가 ALICE의 권한으로 호출할 수 있어 악용 위험이 큽니다.
     */
    function test_SwapWithUnsafeDelegation() public {
        // ALICE가 본인의 unsafe delegation 구현 계약에 대해 delegation 서명을 생성 후 부착
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(unsafeImplementation), ALICE_PVK);
        vm.attachDelegation(signedDelegation);

        // ALICE 계정에 delegation 코드가 부착되었는지 확인 (코드 길이가 0보다 커야 함)
        bytes memory code = ALICE.code;
        assertGt(code.length, 0);

        // BOB가 실행할 호출(Call) 배열 준비:
        // 첫 번째 호출: ALICE의 usdc 토큰에서 swap 계약에 대해 SWAP_AMOUNT 승인 요청
        // 두 번째 호출: swap.swap 함수를 호출하여 USDC를 USDK로 스왑 (1:1 교환)
        SimpleDelegate.Call[] memory calls = new SimpleDelegate.Call[](2);
        calls[0] = SimpleDelegate.Call({
            to: address(usdc),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(swap), SWAP_AMOUNT)
        });
        calls[1] = SimpleDelegate.Call({
            to: address(swap),
            value: 0,
            data: abi.encodeWithSelector(SimpleSwap.swap.selector, address(usdc), address(usdk), SWAP_AMOUNT, SWAP_AMOUNT)
        });

        // BOB가 ALICE에 부착된 unsafe delegation의 execute 함수를 호출하여 위 call 배열을 실행시킵니다.
        vm.prank(BOB);
        SimpleDelegate(payable(ALICE)).execute(calls);

        // 교환 후 결과 검증:
        // - ALICE의 USDC 잔액은 SWAP_AMOUNT만큼 감소.
        // - ALICE의 USDK 잔액은 SWAP_AMOUNT만큼 증가.
        // - swap 계약의 잔액 역시 각각 USDC는 SWAP_AMOUNT, USDK는 MINT_AMOUNT - SWAP_AMOUNT로 변함.
        assertEq(usdc.balanceOf(ALICE), MINT_AMOUNT - SWAP_AMOUNT);
        assertEq(usdk.balanceOf(ALICE), SWAP_AMOUNT);
        assertEq(usdc.balanceOf(address(swap)), SWAP_AMOUNT);
        assertEq(usdk.balanceOf(address(swap)), MINT_AMOUNT - SWAP_AMOUNT);
    }

    /**
     * @notice 시나리오: Unsafe delegation을 악의적으로 활용하여 ALICE의 모든 USDC 토큰을 BOB로 전송.
     * @dev 수행 단계:
     *  1. ALICE가 자신의 unsafe delegation 서명을 생성하여 계정에 부착합니다 (startDelegation 헬퍼 사용).
     *  2. BOB는 단 하나의 call 배열을 준비하여, ALICE의 USDC 잔액 전체를 BOB 주소로 전송하도록 요청합니다.
     *  3. BOB가 ALICE의 unsafe delegation의 execute 함수를 호출함으로써, ALICE의 전체 USDC가 BOB로 이동합니다.
     *  4. 최종적으로 ALICE의 USDC 잔액은 0이 되고, BOB의 USDC 잔액은 이전 ALICE 잔액만큼 증가했음을 확인합니다.
     */
    function test_MaliciousTransferWithUnsafeDelegation() public {
        // ALICE가 unsafe delegation 서명을 생성 및 부착 (startDelegation 헬퍼 사용)
        startDelegation(address(unsafeImplementation), ALICE_PVK);

        // BOB가 실행할 호출(Call): ALICE의 전체 USDC 잔액을 BOB로 전송하는 ERC20 transfer 호출
        SimpleDelegate.Call[] memory calls = new SimpleDelegate.Call[](1);
        calls[0] = SimpleDelegate.Call({
            to: address(usdc),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, BOB, usdc.balanceOf(ALICE))
        });

        // ALICE의 현재 USDC 잔액 저장 (이 값을 나중에 BOB의 잔액 증가 확인에 사용)
        uint256 aliceUsdcBalance = usdc.balanceOf(ALICE);

        // BOB가 ALICE의 unsafe delegation execute 호출을 통해 USDC 전체 전송 실행
        vm.prank(BOB);
        SimpleDelegate(payable(ALICE)).execute(calls);

        // 결과 검증:
        // - ALICE의 USDC 잔액은 0이어야 함.
        // - BOB의 USDC 잔액은 ALICE의 이전 잔액만큼 증가했음을 확인.
        assertEq(usdc.balanceOf(ALICE), 0);
        assertEq(usdc.balanceOf(BOB), aliceUsdcBalance);
    }

    /**
     * @notice 시나리오: Safe delegation 방식으로 ALICE가 자신의 토큰 스왑 호출을 실행하는 경우.
     * @dev 수행 단계:
     *  1. ALICE가 자신의 safe delegation 서명을 생성하여 계정에 부착합니다 (startDelegation 헬퍼 사용).
     *  2. ALICE는 ERC20 approve와 swap 호출을 포함하는 call 배열을 준비합니다 (prepareSwapCalls 헬퍼 사용).
     *  3. 오직 ALICE 자신만이 safe delegation의 execute 함수를 호출하여 위 call 배열을 실행할 수 있습니다.
     *  4. 최종적으로 ALICE와 swap 계약의 토큰 잔액이 예상대로 변경되었는지 확인합니다.
     */
    function test_SwapWithSafeDelegation() public {
        // ALICE가 safe delegation 서명을 생성 및 부착
        startDelegation(address(safeImplementation), ALICE_PVK);

        // ALICE가 실행할 호출(Call) 배열 준비:
        // - 첫 번째 call: ALICE의 usdc에서 swap 계약에 대해 SWAP_AMOUNT 승인
        // - 두 번째 call: swap.swap 함수 호출해서 USDC를 USDK로 교환 (1:1 스왑)
        SimpleDelegate.Call[] memory calls = prepareSwapCalls(address(usdc), address(usdk), SWAP_AMOUNT, SWAP_AMOUNT);

        // ALICE 자신만이 safe delegation을 통해 execute를 호출할 수 있음 (vm.prank(ALICE) 사용)
        vm.prank(ALICE);
        SafeSimpleDelegate(payable(ALICE)).execute(calls);

        // 교환 후 결과 검증:
        // - ALICE의 USDC 잔액이 SWAP_AMOUNT 만큼 감소하고,
        // - ALICE의 USDK 잔액이 SWAP_AMOUNT 만큼 증가하며,
        // - swap 계약의 USDC와 USDK 잔액 역시 각각 SWAP_AMOUNT와 (MINT_AMOUNT - SWAP_AMOUNT)로 변함.
        assertEq(usdc.balanceOf(ALICE), MINT_AMOUNT - SWAP_AMOUNT);
        assertEq(usdc.balanceOf(address(swap)), SWAP_AMOUNT);
        assertEq(usdk.balanceOf(ALICE), SWAP_AMOUNT);
        assertEq(usdk.balanceOf(address(swap)), MINT_AMOUNT - SWAP_AMOUNT);
    }

    /**
     * @notice 시나리오: ALICE가 safe delegation 서명을 부착했을 때, ALICE가 아닌 다른 계정(예: BOB)이 execute를 호출하면 실패.
     * @dev 수행 단계:
     *  1. ALICE가 safe delegation 서명을 생성하여 자신의 계정에 부착합니다.
     *  2. BOB가 호출(Call) 배열(approve 및 swap 호출 포함)을 준비합니다.
     *  3. BOB가 safe delegation의 execute 함수를 호출 시, OnlySelf 접근제한에 의해 revert되어야 합니다.
     *     - vm.expectRevert에 SafeSimpleDelegate.OnlySelf.selector를 설정하여 이를 검증합니다.
     */
    function test_Revert_SwapWithSafeDelegationNotSelf() public {
        // ALICE가 safe delegation 서명을 생성 및 부착
        startDelegation(address(safeImplementation), ALICE_PVK);

        // 호출(Call) 배열 준비: ALICE의 usdc 승인 및 swap 호출 포함
        SimpleDelegate.Call[] memory calls = prepareSwapCalls(address(usdc), address(usdk), SWAP_AMOUNT, SWAP_AMOUNT);

        // BOB가 execute 호출 시, safe delegation의 OnlySelf 제약 조건으로 인해 revert 되어야 함을 예상
        vm.expectRevert(SafeSimpleDelegate.OnlySelf.selector);

        // BOB가 ALICE의 safe delegation execute 함수를 호출 => revert expected
        vm.prank(BOB);
        SafeSimpleDelegate(payable(ALICE)).execute(calls);
    }

    /**
     * @notice 헬퍼 함수: 주어진 delegation 구현 계약 주소와 개인키를 사용해 delegation 서명을 생성 및 부착합니다.
     * @param implementation delegation을 적용할 대상 구현 계약 주소
     * @param pvKey 개인키 값 (예, ALICE_PVK 또는 BOB_PVK)
     *
     * @dev 이 함수는 delegation 서명을 생성한 후 vm.attachDelegation을 호출하여
     *      해당 서명을 현재 호출 컨텍스트의 msg.sender에 부착합니다.
     */
    function startDelegation(address implementation, uint256 pvKey) public {
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(implementation, pvKey);
        vm.attachDelegation(signedDelegation);
    }

    /**
     * @notice 헬퍼 함수: 두 call을 포함하는 배열을 준비하여, token swap에 필요한 호출 정보를 생성합니다.
     * @param tokenIn USDC와 같은 입력 토큰 주소
     * @param tokenOut USDK와 같은 출력 토큰 주소
     * @param amountIn 입력 토큰의 승인 금액 (SWAP_AMOUNT)
     * @param amountOut swap 후 받을 출력 토큰의 수량 (SWAP_AMOUNT)
     *
     * @dev 반환되는 call 배열은 아래 두 호출(call)을 포함합니다:
     *  1. tokenIn(예: USDC)에 대해 swap 계약에 SWAP_AMOUNT 승인 호출.
     *  2. swap.swap 함수를 호출하여 tokenIn을 tokenOut으로 스왑하는 호출.
     */
    function prepareSwapCalls(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)
        public
        view
        returns (SimpleDelegate.Call[] memory calls)
    {
        calls = new SimpleDelegate.Call[](2);
        // 첫 번째 Call: tokenIn(USDC)에 대해 swap 계약에 토큰 전송 권한을 부여 (approve)
        calls[0] = SimpleDelegate.Call({
            to: address(tokenIn),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, address(swap), amountIn)
        });
        // 두 번째 Call: swap.swap 함수를 호출하여 실제 토큰 교환을 수행
        calls[1] = SimpleDelegate.Call({
            to: address(swap),
            value: 0,
            data: abi.encodeWithSelector(SimpleSwap.swap.selector, tokenIn, tokenOut, amountIn, amountOut)
        });
    }
}
