const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

// decimals

describe("marketplace", function () {
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function deploy() {
        // Contracts are deployed using the first signer/account by default
        const [owner, otherAccount, a1, a2, a3, a4, a5] =
            await ethers.getSigners();

        const Marketplace = await ethers.getContractFactory("NftMarketplace");
        const marketplace = await Marketplace.deploy(500, 15, 200, 10000);

        const Rakmans = await ethers.getContractFactory("Rakmans");
        const rakmansNFT = await Rakmans.deploy(owner);

        const RakmansERC1155 = await ethers.getContractFactory(
            "RakmansERC1155"
        );
        const rakmansERC1155 = await RakmansERC1155.deploy(otherAccount);

        const Ether = await ethers.getContractFactory("Ether");
        const ether = await Ether.deploy();

        await ether.transfer(otherAccount, 1000);

        return {
            rakmansERC1155,
            rakmansNFT,
            marketplace,
            ether,
            owner,
            otherAccount,
            a1,
            a2,
            a3,
            a4,
            a5,
        };
    }
    describe("create and edit", async () => {
        it("test with address(0)", async () => {
            const { rakmansNFT, ether, marketplace, owner, otherAccount } =
                await loadFixture(deploy);
            await rakmansNFT.safeMint(otherAccount, "rakmansNFT.github.io");
            await rakmansNFT
                .connect(otherAccount)
                .approve(marketplace.getAddress(), 0);
            await expect(
                marketplace
                    .connect(otherAccount)
                    .createList(
                        "0x0000000000000000000000000000000000000000",
                        0,
                        await ether.getAddress(),
                        900,
                        1000,
                        1,
                        false
                    )
            ).to.be.reverted;
            await expect(
                marketplace
                    .connect(otherAccount)
                    .createList(
                        await rakmansNFT.getAddress(),
                        0,
                        "0x0000000000000000000000000000000000000000",
                        900,
                        1000,
                        1,
                        false
                    )
            ).to.be.reverted;
        });
        it("create and edit listing", async () => {
            const { rakmansNFT, ether, marketplace, owner, otherAccount } =
                await loadFixture(deploy);
            await rakmansNFT.safeMint(owner, "rakmansNFT.github.io");
            await rakmansNFT.approve(marketplace.getAddress(), 0);
            await expect(marketplace.getListing(0)).to.be.reverted;
            await marketplace.createList(
                await rakmansNFT.getAddress(),
                0,
                await ether.getAddress(),
                10,
                1000,
                100,
                false
            );
            let listing = await marketplace.getListing(0);
            expect(listing.tokenContract).to.equal(
                await rakmansNFT.getAddress()
            );
            expect(listing.id).to.equal(0);
            expect(listing.paymentToken).to.equal(await ether.getAddress());
            expect(listing.price).to.equal(10);
            expect(listing.end).to.equal((await time.latest()) + 1000);
            expect(listing.quantity).to.equal(1);
            expect(listing.isAuction).to.equal(false);
            await marketplace.editListing(
                0,
                await ether.getAddress(),
                100,
                1000,
                1
            );
            listing = await marketplace.getListing(0);
            expect(listing.tokenContract).to.equal(
                await rakmansNFT.getAddress()
            );
            expect(listing.id).to.equal(0);
            expect(listing.paymentToken).to.equal(await ether.getAddress());
            expect(listing.price).to.equal(100);
            expect(listing.end).to.equal((await time.latest()) + 1000);
            expect(listing.quantity).to.equal(1);
            expect(listing.isAuction).to.equal(false);
            await expect(
                marketplace
                    .connect(otherAccount)
                    .editListing(0, await ether.getAddress(), 1000, 2000, 1)
            ).to.be.reverted;
        });
    });
    describe("ERC721", () => {
        describe("Sale", () => {
            it("Sale type 1", async () => {
                const { rakmansNFT, ether, marketplace, owner, otherAccount } =
                    await loadFixture(deploy);
                await rakmansNFT.safeMint(otherAccount, "rakmansNFT.github.io");
                await rakmansNFT
                    .connect(otherAccount)
                    .approve(marketplace.getAddress(), 0);
                await marketplace
                    .connect(otherAccount)
                    .createList(
                        await rakmansNFT.getAddress(),
                        0,
                        await ether.getAddress(),
                        900,
                        1000,
                        1,
                        false
                    );
                await ether.approve(marketplace, 900);
                await marketplace.buy(0, 1);
                expect(await rakmansNFT.ownerOf(0)).to.equal(owner);
                expect(await ether.balanceOf(otherAccount)).to.equal(1837);
                expect(await ether.balanceOf(owner)).to.equal(8163);
            });
        });
        describe("Auction", async function () {
            it("Auction type 1", async () => {
                const {
                    rakmansNFT,
                    ether,
                    marketplace,
                    owner,
                    a1,
                    a2,
                    a3,
                    a4,
                    a5,
                } = await loadFixture(deploy);
                await ether.transfer(a1, 1000);
                await ether.transfer(a2, 1000);
                await ether.transfer(a3, 1000);
                await ether.transfer(a4, 1000);
                await ether.transfer(a5, 1000);
                await rakmansNFT.safeMint(owner, "rakmansNFT.github.io");
                await rakmansNFT.approve(marketplace.getAddress(), 0);
                await marketplace.createList(
                    rakmansNFT.getAddress(),
                    0,
                    ether.getAddress(),
                    200,
                    1000,
                    1,
                    true
                );
                await ether.connect(a1).approve(marketplace.getAddress(), 220);
                await marketplace.connect(a1).bid(0, 205, 1);
                await ether.connect(a2).approve(marketplace.getAddress(), 250);
                await expect(marketplace.connect(a2).bid(0, 210, 1)).to.be
                    .reverted;
                await expect(marketplace.connect(a2).bid(0, 205, 1)).to.be
                    .reverted;
                await marketplace.connect(a2).bid(0, 250, 1);
                await ether.connect(a3).approve(marketplace.getAddress(), 350);
                await marketplace.connect(a3).bid(0, 350, 1);
                await ether.connect(a4).approve(marketplace.getAddress(), 420);
                await marketplace.connect(a4).bid(0, 420, 1);
                await ether.connect(a5).approve(marketplace.getAddress(), 500);
                await marketplace.connect(a5).bid(0, 500, 1);
                await ether.connect(a4).approve(marketplace.getAddress(), 900);
                await marketplace.connect(a4).bid(0, 900, 1);
                await expect(marketplace.closeAuction(0)).to.be.reverted;
                await time.increase(1000);
                await ether.connect(a3).approve(marketplace.getAddress(), 350);
                await expect(marketplace.connect(a3).bid(0, 350, 1)).to.be
                    .reverted;
                const listingBids = await marketplace.getListingBids(0);
                const highestBidder = listingBids[listingBids.length - 1][0];
                expect(highestBidder).to.be.equal(a4);
                const beforeOwnerBal = await ether.balanceOf(owner);
                await marketplace.connect(a4).closeAuction(0);
                const ownerBal = await ether.balanceOf(owner);
                expect(ownerBal).to.be.equal(beforeOwnerBal + 900n);
                await expect(marketplace.closeAuction(0)).to.be.reverted;
                const withdrawMony = async (a) => {
                    const beforeBal = await ether.balanceOf(a);
                    const bidsAmount = await marketplace.getUserBidBalance(
                        0,
                        a
                    );
                    await marketplace.connect(a).withdrawal(0);
                    expect(
                        (await marketplace.getUserBidBalance(0, a)).bid
                    ).to.be.equal(0);
                    expect(await ether.balanceOf(a)).to.be.equal(
                        beforeBal + bidsAmount.bid
                    );
                };
                await withdrawMony(a1);
                await withdrawMony(a2);
                await withdrawMony(a3);
                await expect(withdrawMony(a4)).to.be.reverted;
                await withdrawMony(a5);
                expect(await rakmansNFT.ownerOf(0)).to.be.equal(highestBidder);
            });
        });
    });
    describe("ERC1155", () => {
        // it("test with ERC1155 sale mode listing", async () => {
        //     const { rakmansERC1155, ether, marketplace, owner } =
        //         await loadFixture(deploy);
        //     await rakmansERC1155.mint(
        //         owner,
        //         0,
        //         10,
        //         "0x0000000000000000000000000000000000000000000000000000000000000000"
        //     );
        //     await rakmansERC1155.setApprovalForAll(
        //         marketplace.getAddress(),
        //         true
        //     );
        //     await marketplace.createList(
        //         rakmansERC1155.getAddress(),
        //         0,
        //         ether.getAddress(),
        //         100,
        //         1000,
        //         10,
        //         false
        //     );
        //     const listing = await marketplace.getListing(0);
        // });
        describe("Sale", async () => {
            it("Sale type 1", async () => {
                const {
                    rakmansERC1155,
                    ether,
                    marketplace,
                    owner,
                    otherAccount,
                } = await loadFixture(deploy);
                await rakmansERC1155
                    .connect(otherAccount)
                    .mint(
                        otherAccount,
                        0,
                        10,
                        "0x0000000000000000000000000000000000000000000000000000000000000000"
                    );
                await rakmansERC1155
                    .connect(otherAccount)
                    .setApprovalForAll(marketplace.getAddress(), true);
                await marketplace
                    .connect(otherAccount)
                    .createList(rakmansERC1155, 0, ether, 100, 1000, 10, false);
                await ether.approve(marketplace, 1000);
                await marketplace.buy(0, 10);
                expect(await rakmansERC1155.balanceOf(owner, 0)).to.be.equal(
                    10n
                );
                expect(await ether.balanceOf(otherAccount)).to.be.equal(1980n);
            });
            it("Sale type 2", async () => {
                const {
                    rakmansERC1155,
                    ether,
                    marketplace,
                    owner,
                    otherAccount,
                    a1,
                    a2,
                } = await loadFixture(deploy);
                await rakmansERC1155
                    .connect(otherAccount)
                    .mint(
                        otherAccount,
                        0,
                        10,
                        "0x0000000000000000000000000000000000000000000000000000000000000000"
                    );
                await ether.transfer(a1, 600);
                await ether.transfer(a2, 300);
                await rakmansERC1155
                    .connect(otherAccount)
                    .setApprovalForAll(marketplace.getAddress(), true);
                await marketplace
                    .connect(otherAccount)
                    .createList(rakmansERC1155, 0, ether, 100, 1000, 10, false);
                await ether.approve(marketplace, 400);
                await marketplace.buy(0, 4);
                expect(await rakmansERC1155.balanceOf(owner, 0)).to.be.equal(4);
                expect(await ether.balanceOf(otherAccount)).to.be.equal(1392n);
                await ether.connect(a1).approve(marketplace, 600);
                await marketplace.connect(a1).buy(0, 6);
                expect(await rakmansERC1155.balanceOf(a1, 0)).to.be.equal(6);
                expect(await ether.balanceOf(otherAccount)).to.be.equal(1980n);
                await ether.connect(a2).approve(marketplace, 300);
                await expect(marketplace.connect(a2).buy(0, 3)).to.be.reverted;
            });
        });
        describe("Auction", async () => {
            it("Auction type 1", async () => {
                const {
                    rakmansERC1155,
                    ether,
                    otherAccount,
                    marketplace,
                    owner,
                    a1,
                    a2,
                    a3,
                    a4,
                    a5,
                } = await loadFixture(deploy);
                await ether.transfer(a1, 1000);
                await ether.transfer(a2, 1000);
                await ether.transfer(a3, 1000);
                await ether.transfer(a4, 1000);
                await ether.transfer(a5, 1000);
                await ether.transfer(otherAccount, 1000);
                await rakmansERC1155.connect(otherAccount).mint(
                    otherAccount,
                    0,
                    10,
                    "0x0000000000000000000000000000000000000000000000000000000000000000"
                );
                await rakmansERC1155.connect(otherAccount).setApprovalForAll(
                    marketplace.getAddress(),
                    true
                );
                await marketplace.connect(otherAccount).createList(
                    rakmansERC1155,
                    0,
                    ether,
                    5,
                    1000,
                    10,
                    true
                );
                await ether.connect(a1).approve(marketplace.getAddress(), 40);
                await marketplace.connect(a1).bid(0, 10, 4);
                await ether.connect(a2).approve(marketplace.getAddress(), 90);
                await expect(marketplace.connect(a2).bid(0, 20, 1)).to.be
                    .reverted;
                await expect(marketplace.connect(a2).bid(0, 3, 10)).to.be
                    .reverted;
                await marketplace.connect(a2).bid(0, 30, 3);
                await ether.connect(a3).approve(marketplace.getAddress(), 150);
                await marketplace.connect(a3).bid(0, 30, 5);
                await ether.connect(a4).approve(marketplace.getAddress(), 160);
                await marketplace.connect(a4).bid(0, 20, 8);
                await ether.connect(a5).approve(marketplace.getAddress(), 300);
                await marketplace.connect(a5).bid(0, 30, 10);
                await ether.connect(a4).approve(marketplace.getAddress(), 1000);
                await marketplace.connect(a4).bid(0, 80, 10);
                await expect(marketplace.closeAuction(0)).to.be.reverted;
                await time.increase(1000);
                await ether.connect(a3).approve(marketplace.getAddress(), 900);
                await expect(marketplace.connect(a3).bid(0, 90, 10)).to.be
                    .reverted;
                const listingBids = await marketplace.getListingBids(0);
                const highestBidder = listingBids[listingBids.length - 1][0];
                expect(highestBidder).to.be.equal(a4);
                const beforeOwnerBal = await ether.balanceOf(otherAccount);
                await marketplace.connect(a4).closeAuction(0);
                const ownerBal = await ether.balanceOf(otherAccount);
                expect(ownerBal).to.be.equal(beforeOwnerBal + 784n);
                const withdrawMony = async (a) => {
                    const beforeBal = await ether.balanceOf(a);
                    const bidsAmount = await marketplace.getUserBidBalance(
                        0,
                        a
                    );
                    await marketplace.connect(a).withdrawal(0);
                    expect(
                        (await marketplace.getUserBidBalance(0, a)).bid
                    ).to.be.equal(0);
                    expect(await ether.balanceOf(a)).to.be.equal(
                        beforeBal + bidsAmount.bid * bidsAmount.quantity
                    );
                };
                await withdrawMony(a1);
                await withdrawMony(a2);
                await withdrawMony(a3);
                await expect(withdrawMony(a4)).to.be.reverted;
                await withdrawMony(a5);
                expect(await rakmansERC1155.balanceOf(highestBidder,0)).to.be.equal(10n);
            });
        });
    });
});
