// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwarmPepes} from "../src/SwarmPepes.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase, Vm} from "./support/TestBase.sol";

/// @dev Local factory stand-in. It has no deployment configuration or environment dependencies.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (SwarmPepes) {
        return new SwarmPepes{salt: salt}();
    }

    function move(SwarmPepes token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "factory transfer failed");
    }
}

contract SwarmPepesTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA401);
    SwarmPepes internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SwarmPepes();
    }

    function test_MetadataAndEntireSupply() public view {
        assertEq(keccak256(bytes(token.name())), keccak256("Swarm Pepes"), "name");
        assertEq(keccak256(bytes(token.symbol())), keccak256("SWARMPEPES"), "symbol");
        assertEq(token.decimals(), 18, "decimals");
        assertEq(token.totalSupply(), SUPPLY, "total supply");
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "initial supply");
        assertEq(token.balanceOf(address(this)), SUPPLY, "deployer holds everything");
        assertEq(token.balanceOf(address(token)), 0, "token balance");
        assertEq(token.balanceOf(address(0)), 0, "zero balance");
        assertEq(token.balanceOf(ALICE), 0, "other balance");
        assertEq(token.allowance(address(this), ALICE), 0, "initial allowance");
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        SwarmPepes deployed = new SwarmPepes();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one mint event");
        assertEq(logs[0].emitter, address(deployed), "mint emitter");
        assertEq(logs[0].topics.length, 3, "mint topic count");
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"), "mint signature");
        assertEq(logs[0].topics[1], bytes32(0), "mint source");
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))), "mint recipient");
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY, "mint amount");
    }

    function test_DirectDeploymentMintsToCaller() public {
        vm.prank(ALICE);
        SwarmPepes deployed = new SwarmPepes();
        assertEq(deployed.balanceOf(ALICE), SUPPLY, "direct deployer receives supply");
        assertEq(deployed.balanceOf(address(this)), 0, "test contract receives nothing");
    }

    function test_FactoryDeploymentAndExactLaunchTransfers() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        SwarmPepes deployed = factory.deploy(bytes32(uint256(7)));
        assertEq(deployed.balanceOf(address(factory)), SUPPLY, "factory receives supply");
        assertEq(deployed.balanceOf(address(this)), 0, "factory caller receives nothing");

        // Exercise token-side distributor, pool and remainder flows with illustrative allocations.
        // This is not a Uniswap pool or the external network's full launch harness.
        address distributor = address(0xD157);
        address poolManager = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY / 2;
        uint256 remainder = SUPPLY - swarm - pool;
        factory.move(deployed, distributor, swarm);
        factory.move(deployed, poolManager, pool);
        factory.move(deployed, CAROL, remainder);
        assertEq(deployed.balanceOf(distributor), swarm, "distributor receives exact share");
        assertEq(deployed.balanceOf(poolManager), pool, "pool receives exact amount");
        assertEq(deployed.balanceOf(CAROL), remainder, "requester receives remainder");
        assertEq(deployed.balanceOf(address(factory)), 0, "all supply forwarded");

        vm.prank(distributor);
        require(deployed.transfer(ALICE, swarm), "claim transfer");
        assertEq(deployed.balanceOf(ALICE), swarm, "claim arrives whole");
        assertEq(deployed.balanceOf(distributor), 0, "claim empties distributor");
        vm.prank(poolManager);
        require(deployed.transfer(BOB, 100 ether), "pool output");
        assertEq(deployed.balanceOf(BOB), 100 ether, "trader receives exact output");
        vm.prank(BOB);
        require(deployed.transfer(poolManager, 100 ether), "pool input");
        assertEq(deployed.balanceOf(BOB), 0, "trader can return tokens");
        assertEq(deployed.balanceOf(poolManager), pool, "pool input arrives whole");
        assertEq(deployed.totalSupply(), SUPPLY, "launch preserves supply");
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 123 ether);
        require(token.transfer(ALICE, 123 ether), "transfer returns true");
        assertEq(token.balanceOf(ALICE), 123 ether, "recipient amount");
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether, "sender amount");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_TransferEntireBalance() public {
        require(token.transfer(ALICE, SUPPLY), "full transfer");
        assertEq(token.balanceOf(address(this)), 0, "sender emptied");
        assertEq(token.balanceOf(ALICE), SUPPLY, "recipient holds all");
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        require(token.transfer(BOB, 0), "zero transfer");
        assertEq(token.balanceOf(ALICE), 0, "sender unchanged");
        assertEq(token.balanceOf(BOB), 0, "recipient unchanged");
    }

    function test_SelfTransferPreservesBalance() public {
        require(token.transfer(address(this), SUPPLY), "self transfer");
        assertEq(token.balanceOf(address(this)), SUPPLY, "self balance unchanged");
        assertEq(token.totalSupply(), SUPPLY, "self transfer supply");
    }

    function test_TransferAboveBalanceRevertsWithoutChanges() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY, "sender unchanged");
        assertEq(token.balanceOf(ALICE), 0, "recipient unchanged");
    }

    function test_SelfTransferStillRequiresBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(ALICE, 1);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.totalSupply(), SUPPLY, "zero address cannot burn");
        assertEq(token.balanceOf(address(this)), SUPPLY, "failed transfer preserves balance");
    }

    function test_ApproveEmitsEventAndCanReplaceAndRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), ALICE, 12 ether);
        require(token.approve(ALICE, 12 ether), "approval returns true");
        assertEq(token.allowance(address(this), ALICE), 12 ether, "approval stored");
        require(token.approve(ALICE, 4 ether), "replace approval");
        assertEq(token.allowance(address(this), ALICE), 4 ether, "approval replaces");
        require(token.approve(ALICE, 0), "revoke approval");
        assertEq(token.allowance(address(this), ALICE), 0, "approval revoked");
        assertEq(token.balanceOf(address(this)), SUPPLY, "approval does not move tokens");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0, "zero spender has no allowance");
    }

    function test_TransferFromMovesTokensAndConsumesAllowance() public {
        require(token.approve(ALICE, 20 ether), "approve");
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), BOB, 7 ether);
        vm.prank(ALICE);
        require(token.transferFrom(address(this), BOB, 7 ether), "delegated transfer");
        assertEq(token.balanceOf(BOB), 7 ether, "recipient amount");
        assertEq(token.balanceOf(address(this)), SUPPLY - 7 ether, "owner amount");
        assertEq(token.allowance(address(this), ALICE), 13 ether, "remaining allowance");
        vm.prank(ALICE);
        require(token.transferFrom(address(this), BOB, 13 ether), "consume remaining allowance");
        assertEq(token.allowance(address(this), ALICE), 0, "allowance exhausted");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(BOB), 20 ether, "extra spend failed");
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        require(token.approve(ALICE, type(uint256).max), "approve max");
        vm.prank(ALICE);
        require(token.transferFrom(address(this), BOB, SUPPLY), "transfer with max allowance");
        assertEq(token.allowance(address(this), ALICE), type(uint256).max, "infinite allowance retained");
        assertEq(token.balanceOf(BOB), SUPPLY, "full amount received");
    }

    function test_TransferFromCannotUseAnotherSpendersApproval() public {
        require(token.approve(ALICE, 1 ether), "approve Alice");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, CAROL, 0, 1));
        vm.prank(CAROL);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), ALICE), 1 ether, "Alice allowance unchanged");
        assertEq(token.balanceOf(address(this)), SUPPLY, "owner balance unchanged");
    }

    function test_TransferFromAboveAllowanceRollsBack() public {
        require(token.approve(ALICE, 3), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 3, 4));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 4);
        assertEq(token.allowance(address(this), ALICE), 3, "allowance unchanged");
        assertEq(token.balanceOf(address(this)), SUPPLY, "owner unchanged");
        assertEq(token.balanceOf(BOB), 0, "recipient unchanged");
    }

    function test_TransferFromAboveBalanceRollsBackAllowance() public {
        require(token.approve(ALICE, SUPPLY + 1), "approve more than balance");
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, SUPPLY + 1);
        assertEq(token.allowance(address(this), ALICE), SUPPLY + 1, "allowance restored");
        assertEq(token.balanceOf(address(this)), SUPPLY, "owner unchanged");
        assertEq(token.balanceOf(BOB), 0, "recipient unchanged");
    }

    function test_TransferFromToZeroRollsBackAllowance() public {
        require(token.approve(ALICE, 2), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(address(this), address(0), 1);
        assertEq(token.allowance(address(this), ALICE), 2, "allowance restored");
        assertEq(token.totalSupply(), SUPPLY, "cannot burn through transferFrom");
    }

    function test_TransferFromZeroSenderReverts() public {
        // Allowance spending rejects a zero owner before the transfer validates its sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        require(token.transferFrom(ALICE, BOB, 0), "zero delegated transfer");
        assertEq(token.allowance(ALICE, address(this)), 0, "allowance unchanged");
        assertEq(token.balanceOf(ALICE), 0, "owner unchanged");
        assertEq(token.balanceOf(BOB), 0, "recipient unchanged");
    }

    function test_DelegatedSelfTransferConsumesAllowanceButPreservesBalance() public {
        require(token.approve(ALICE, SUPPLY), "approve");
        vm.prank(ALICE);
        require(token.transferFrom(address(this), address(this), SUPPLY), "delegated self transfer");
        assertEq(token.balanceOf(address(this)), SUPPLY, "self balance unchanged");
        assertEq(token.allowance(address(this), ALICE), 0, "allowance consumed");
    }

    function test_DeployerCannotMoveHolderTokensWithoutApproval() public {
        require(token.transfer(ALICE, 100 ether), "fund holder");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100 ether, "holder keeps tokens");
    }

    function test_NoMintBurnOrAdministrativeEntryPoints() public {
        require(token.transfer(BOB, 100 ether), "fund holder");
        bytes[] memory calls = new bytes[](16);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", ALICE, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1);
        calls[4] = abi.encodeWithSignature("initialize(address)", ALICE);
        calls[5] = abi.encodeWithSignature("upgradeTo(address)", ALICE);
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", ALICE);
        calls[7] = abi.encodeWithSignature("setMinter(address)", ALICE);
        calls[8] = abi.encodeWithSignature("pause()");
        calls[9] = abi.encodeWithSignature("blacklist(address)", BOB);
        calls[10] = abi.encodeWithSignature("freeze(address)", BOB);
        calls[11] = abi.encodeWithSignature("setBlacklist(address,bool)", BOB, true);
        calls[12] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[13] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[14] = abi.encodeWithSignature("burnFrom(address,uint256)", BOB, 1);
        calls[15] = abi.encodeWithSignature("seize(address)", BOB);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerOk,) = address(token).call(calls[i]);
            require(!deployerOk, "deployer reached an unexpected entry point");
            vm.prank(ALICE);
            (bool strangerOk,) = address(token).call(calls[i]);
            require(!strangerOk, "stranger reached an unexpected entry point");
            assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
            assertEq(token.balanceOf(BOB), 100 ether, "holder balance unchanged");
            assertEq(token.balanceOf(ALICE), 0, "stranger receives nothing");
        }
        vm.prank(BOB);
        require(token.transfer(CAROL, 100 ether), "holder remains able to transfer");
        assertEq(token.balanceOf(CAROL), 100 ether, "holder transfer arrives whole");
    }

    function test_RejectsNativeCurrency() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1 ether}("");
        require(!ok, "token should reject ordinary native deposits");
        assertEq(address(token).balance, 0, "no native currency accepted");
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        require(runtime.length > 0 && runtime.length <= 24_576, "deployable runtime size");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            require(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_TransferConservesSupply(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        require(token.transfer(ALICE, amount), "fuzz transfer");
        assertEq(token.balanceOf(ALICE), amount, "exact recipient balance");
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "exact sender balance");
        assertEq(token.totalSupply(), SUPPLY, "constant supply");
    }

    function testFuzz_TransferFromConservesSupplyAndAllowance(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approved = rawApproval % (SUPPLY + 1);
        uint256 amount = rawAmount % (approved + 1);
        require(token.approve(ALICE, approved), "fuzz approval");
        vm.prank(ALICE);
        require(token.transferFrom(address(this), BOB, amount), "fuzz delegated transfer");
        assertEq(token.allowance(address(this), ALICE), approved - amount, "exact allowance");
        assertEq(token.balanceOf(BOB), amount, "exact recipient balance");
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "exact owner balance");
        assertEq(token.totalSupply(), SUPPLY, "constant supply");
    }

    function testFuzz_InsufficientBalanceAlwaysReverts(uint256 rawExcess) public {
        uint256 amount = SUPPLY + 1 + rawExcess % (type(uint256).max - SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY, "failed transfer preserves balance");
        assertEq(token.balanceOf(ALICE), 0, "failed transfer gives nothing");
    }

    function testFuzz_SequenceMatchesBalanceModel(bytes32 seed) public {
        address[4] memory actors = [address(this), ALICE, BOB, CAROL];
        uint256[4] memory model = [SUPPLY, uint256(0), uint256(0), uint256(0)];
        for (uint256 i; i < 32; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint256 from = entropy % 4;
            uint256 to = (entropy >> 8) % 4;
            uint256 amount = (entropy >> 16) % (model[from] + 1);
            if (i % 2 == 0) {
                vm.prank(actors[from]);
                require(token.transfer(actors[to], amount), "sequence transfer");
            } else {
                address spender = actors[(from + 1) % 4];
                vm.prank(actors[from]);
                require(token.approve(spender, amount), "sequence approval");
                vm.prank(spender);
                require(token.transferFrom(actors[from], actors[to], amount), "sequence delegated transfer");
                assertEq(token.allowance(actors[from], spender), 0, "sequence allowance consumed");
            }
            model[from] -= amount;
            model[to] += amount;
            uint256 sum;
            for (uint256 j; j < actors.length; ++j) {
                uint256 balance = token.balanceOf(actors[j]);
                assertEq(balance, model[j], "balance matches independent model");
                sum += balance;
            }
            assertEq(sum, SUPPLY, "balances conserve supply");
            assertEq(token.totalSupply(), SUPPLY, "supply never changes");
            assertEq(token.balanceOf(address(0)), 0, "no tokens burned");
        }
    }
}
