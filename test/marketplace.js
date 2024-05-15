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
        const rakmansERC1155 = await RakmansERC1155.deploy(owner);

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

    describe("create and edit listing", function () {
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
            await rakmansNFT.safeMint(otherAccount, "rakmansNFT.github.io");
            await rakmansNFT
                .connect(otherAccount)
                .approve(marketplace.getAddress(), 0);
            // less than 10 (decimals)
            await marketplace
                .connect(otherAccount)
                .createList(
                    rakmansNFT.getAddress(),
                    0,
                    ether.getAddress(),
                    900,
                    1000,
                    1,
                    false
                );
            const listing = await marketplace.getListing(0);
            await ether.approve(marketplace, 900);
            await marketplace.buy(0, 1);
            expect(await rakmansNFT.ownerOf(0)).to.equal(owner);
            expect(await ether.balanceOf(otherAccount)).to.equal(1837);
            expect(await ether.balanceOf(owner)).to.equal(8163);
        });
        it("test with ERC721 Auction mode listing", async function () {
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
            await marketplace.connect(a1).bid(0, 205);
            await ether.connect(a2).approve(marketplace.getAddress(), 250);
            await expect(marketplace.connect(a2).bid(0, 210)).to.be.reverted;
            await expect(marketplace.connect(a2).bid(0, 205)).to.be.reverted;
            await marketplace.connect(a2).bid(0, 250);
            await ether.connect(a3).approve(marketplace.getAddress(), 350);
            await marketplace.connect(a3).bid(0, 350);
            await ether.connect(a4).approve(marketplace.getAddress(), 420);
            await marketplace.connect(a4).bid(0, 420);
            await ether.connect(a5).approve(marketplace.getAddress(), 500);
            await marketplace.connect(a5).bid(0, 500);
            await ether.connect(a4).approve(marketplace.getAddress(), 480);
            await marketplace.connect(a4).bid(0, 480);
            await expect(marketplace.closeAuction(0)).to.be.reverted;
            await time.increase(1000);
            await ether.connect(a3).approve(marketplace.getAddress(), 350);
            await expect(marketplace.connect(a3).bid(0, 350)).to.be.reverted;
            const listingBids = await marketplace.getListingBids(0);
            const highestBidder = listingBids[listingBids.length - 1][0];
            expect(highestBidder).to.be.equal(a4);
            const beforeOwnerBal = await ether.balanceOf(owner);
            await marketplace.connect(a4).closeAuction(0);
            const ownerBal = await ether.balanceOf(owner);
            expect(ownerBal).to.be.equal(beforeOwnerBal + 900n);
            const withdrawMony = async (a) => {
                const beforeBal = await ether.balanceOf(a);
                const bidsAmount = await marketplace.getUserBidBalance(0, a);
                await marketplace.connect(a).withdrawal(0);
                expect(await marketplace.getUserBidBalance(0, a)).to.be.equal(
                    0
                );
                expect(await ether.balanceOf(a)).to.be.equal(
                    beforeBal + bidsAmount
                );
            };
            await withdrawMony(a1);
            await withdrawMony(a2);
            await withdrawMony(a3);
            await expect(withdrawMony(a4)).to.be.reverted;
            await withdrawMony(a5);
            expect(await rakmansNFT.ownerOf(0)).to.be.equal(highestBidder);
        });
        it("test with ERC721 Offer mode listing", async () => {
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
                false
            );

            await ether.connect(a1).approve(marketplace.getAddress(), 160);
            await expect(marketplace.connect(a1).bid(0, 205)).to.be.reverted;
            await expect(marketplace.connect(a1).offer(0, 200,10)).to.be.reverted;
            await expect(marketplace.connect(a1).offer(0, 205,10)).to.be.reverted;
            await marketplace.connect(a1).offer(0, 160,10);

            // await ether.connect(a2).approve(marketplace.getAddress(), 170);
            // await expect(marketplace.connect(a2).offer(0, 160,1)).to.be.reverted;
            // await expect(marketplace.connect(a2).offer(0, 162,1)).to.be.reverted;
            // await marketplace.connect(a2).offer(0, 170,1);

            // await ether.connect(a3).approve(marketplace.getAddress(), 180);
            // await marketplace.connect(a3).offer(0, 180,1);

            // await ether.connect(a1).approve(marketplace.getAddress(), 30);
            // await marketplace.connect(a1).offer(0, 30,1);

            // await time.increase(1500);
            // await ether.connect(a3).approve(marketplace.getAddress(), 350);
            // await expect(marketplace.connect(a3).offer(0, 100)).to.be.reverted;
            // const listingOffers = await marketplace.getListingOffers(0);
            // console.log(listingOffers)
            // const highestBidder = listingBids[listingBids.length - 1][0];
            // expect(highestBidder).to.be.equal(a4);
            // const beforeOwnerBal = await ether.balanceOf(owner);
            // await marketplace.connect(a4).closeAuction(0);
            // const ownerBal = await ether.balanceOf(owner);
            // expect(ownerBal).to.be.equal(beforeOwnerBal + 900n);
            // const withdrawMony = async (a) => {
            //     const beforeBal = await ether.balanceOf(a);
            //     const bidsAmount = await marketplace.getUserBidBalance(0, a);
            //     await marketplace.connect(a).withdrawal(0);
            //     expect(await marketplace.getUserBidBalance(0, a)).to.be.equal(
            //         0
            //     );
            //     expect(await ether.balanceOf(a)).to.be.equal(
            //         beforeBal + bidsAmount
            //     );
            // };
            // await withdrawMony(a1);
            // await withdrawMony(a2);
            // await withdrawMony(a3);
            // await expect(withdrawMony(a4)).to.be.reverted;
            // await withdrawMony(a5);
            // expect(await rakmansNFT.ownerOf(0)).to.be.equal(highestBidder);
        });

        // it("test with ERC721 Auction mode listing", async function () {
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
        //         0,
        //         1000,
        //         10,
        //         10,
        //         true
        //     );
        //     const listing = await marketplace.getListing(0);
        // });
    });
});
