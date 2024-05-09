const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("marketplace", function () {
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function deploy() {
        // Contracts are deployed using the first signer/account by default
        const [owner, otherAccount] = await ethers.getSigners();

        const Marketplace = await ethers.getContractFactory("marketplace");
        const marketplace = await Marketplace.deploy();

        const Rakmans = await ethers.getContractFactory("Rakmans");
        const rakmansNFT = await Rakmans.deploy(owner);

        const RakmansERC1155 = await ethers.getContractFactory(
            "RakmansERC1155"
        );
        const rakmansERC1155 = await RakmansERC1155.deploy(owner);

        const Ether = await ethers.getContractFactory("Ether");
        const ether = await Ether.deploy();

        await ether.transfer(otherAccount, 1000);

        await marketplace.initialize(10000, 500);

        return {
            rakmansERC1155,
            rakmansNFT,
            marketplace,
            ether,
            owner,
            otherAccount,
        };
    }

    describe("crete and edit listing", function () {
        it("edit listing", async () => {
            const { rakmansNFT, ether, marketplace, owner, otherAccount } =
                await loadFixture(deploy);
            await rakmansNFT.safeMint(owner, "rakmansNFT.github.io");
            await rakmansNFT.approve(marketplace.getAddress(), 0);
            await marketplace.createList(
                rakmansNFT.getAddress(),
                0,
                ether.getAddress(),
                10,
                1000,
                1,
                false
            );
            let listing = await marketplace.getListing(0);
            expect(listing.price).to.equal(10);
            await marketplace.editListing(0, ether.getAddress(), 100, 1000, 1);
            listing = await marketplace.getListing(0);
            expect(listing.price).to.equal(100);
        });
    });
    describe("ERC721 Auction and sale test", () => {
        it("test with ERC721 sale mode listing", async function () {
            const { rakmansNFT, ether, marketplace, owner, otherAccount } =
                await loadFixture(deploy);
            await rakmansNFT.safeMint(owner, "rakmansNFT.github.io");
            await rakmansNFT.approve(marketplace.getAddress(), 0);
            await marketplace.createList(
                rakmansNFT.getAddress(),
                0,
                ether.getAddress(),
                10,
                1000,
                1,
                false
            );
            const listing = await marketplace.getListing(0);
            await ether.connect(otherAccount).approve(marketplace, 10);
            await marketplace.connect(otherAccount).buy(0, 1);
            expect(await rakmansNFT.ownerOf(0)).to.equal(otherAccount);
            expect(await ether.balanceOf(owner)).to.equal(9010);
        });
        it("test with ERC721 Auction mode listing", async function () {
            const { rakmansERC1155, ether, marketplace, owner } =
                await loadFixture(deploy);
            await rakmansERC1155.mint(
                owner,
                0,
                10,
                "0x0000000000000000000000000000000000000000000000000000000000000000"
            );
            await rakmansERC1155.setApprovalForAll(
                marketplace.getAddress(),
                true
            );
            await marketplace.createList(
                rakmansERC1155.getAddress(),
                0,
                ether.getAddress(),
                0,
                1000,
                10,
                10,
                true
            );
            const listing = await marketplace.getListing(0);
        });
    });
});
