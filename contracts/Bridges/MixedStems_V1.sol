// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721A.sol";
import "./IERC2981.sol";
import "./Ownable.sol";

error MintingLimitReached();
error SeedAlreadyUsed();
error InvalidProof();
error InsufficientBalance(uint256 balance);
error NotAllowlisted();
error SameLengthRequired();

contract MixedStems_V1 is ERC721A, IERC2981, Ownable {
    using Strings for uint256;
    using Address for address payable;

    type SongID is uint256;
    type TrackID is uint256;

    enum Phase {
        INIT,
        ALLOWLIST,
        PUBLIC,
        RESERVE
    }

    Royalties_V1 public immutable royaltyContract;
    uint256 public royaltyPercent;

    string public baseURI;

    uint256 public numVariableTracks;
    uint256 public mintPrice;
    uint256 public maxSupply;

    // metadata values
    string public composer;
    string private _singular;
    string public description;

    // song ID -> track ID -> array of pointers to SSTORE2 MIDI data
    mapping(SongID => mapping(TrackID => address[])) private _tracks;
    // song ID -> array of pointers to SSTORE2 MIDI data
    mapping(SongID => address[]) private _staticTracks;
    // song ID -> time division
    mapping(SongID => bytes2) private _timeDivisions;
    // tokenID -> variant ID
    mapping(uint256 => uint256) private _variants;
    // song ID -> song name
    mapping(SongID => string) private _songNames;

    Phase public mintingPhase;

    bytes32 private _allSeedsMerkleRoot;
    // tokenID -> seed
    mapping(uint256 => bytes32) private _seeds;
    // seed -> used
    mapping(bytes32 => bool) private _seedUsed;
    // seed -> tokenID
    mapping(bytes32 => uint256) private _seedTokenID;

    bytes32 private _allowlistMerkleRoot;

    // MODIFIERS -----------------------------------------------------

    modifier onlyPhase(Phase _phase) {
        require(mintingPhase == _phase, "Wrong phase");
        _;
    }

    modifier mustPrice(uint256 _price) {
        require(msg.value == _price, "Wrong price");
        _;
    }

    // CONSTRUCTOR ---------------------------------------------------

    constructor(
        string memory baseURI_,
        string memory name_,
        string memory singular_,
        string memory description_,
        string memory symbol_,
        string memory composer_,
        uint256 numVariableTracks_,
        address[] memory royaltyReceivers_,
        uint256[] memory royaltyShares_,
        uint256 royaltyPercent_
    ) ERC721A(name_, symbol_) {
        baseURI = baseURI_;
        _singular = singular_;
        description = description_;
        numVariableTracks = numVariableTracks_;
        composer = composer_;
        Royalties_V1 p = new Royalties_V1(
            royaltyReceivers_,
            royaltyShares_,
            msg.sender
        );
        royaltyContract = p;
        royaltyPercent = royaltyPercent_;
    }

    // ADMIN FUNCTIONS ---------------------------------------------------

    function withdraw(address payable to, uint256 amount) public onlyOwner {
        if (address(this).balance < amount) {
            revert InsufficientBalance(address(this).balance);
        }

        if (amount == 0) {
            amount = address(this).balance;
        }
        if (to == address(0)) {
            to = payable(owner());
        }
        to.sendValue(amount);
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function setComposer(string memory composer_) public onlyOwner {
        composer = composer_;
    }

    function setDescription(string memory description_) public onlyOwner {
        description = description_;
    }
    
    function startAllowlistMint(uint256 supply) public onlyOwner {
        mintingPhase = Phase.ALLOWLIST;
        maxSupply = supply;
    }

    function startPublicMint(uint256 supply) public onlyOwner {
        mintingPhase = Phase.PUBLIC;
        maxSupply = supply;
    }

    function startReserveMint(uint256 supply) public onlyOwner {
        mintingPhase = Phase.RESERVE;
        maxSupply = supply;
    }

    function disableMint() public onlyOwner {
        mintingPhase = Phase.INIT;
    }

    function setMintPrice(uint256 value) public onlyOwner {
        mintPrice = value;
    }

    function setAllSeedsMerkleRoot(bytes32 value) public onlyOwner {
        _allSeedsMerkleRoot = value;
    }

    function setAllowlistMerkleRoot(bytes32 value) public onlyOwner {
        _allowlistMerkleRoot = value;
    }

    function setRoyaltyPercentage(uint256 percent) public onlyOwner {
        royaltyPercent = percent;
    }

    function setSongNames(SongID[] memory songs, string[] memory songNames)
        public
        onlyOwner
    {
        require(songs.length == songNames.length);
        for (uint256 i = 0; i < songNames.length; i++) {
            _songNames[songs[i]] = songNames[i];
        }
    }

    function addVariableTrack(
        SongID song,
        TrackID trackNum,
        bytes calldata track
    ) external onlyOwner {
        require(TrackID.unwrap(trackNum) < numVariableTracks);
        address pointer = SSTORE2.write(track);
        _tracks[song][trackNum].push(pointer);
    }

    function removeVariableTrack(
        SongID song,
        TrackID trackNum,
        uint256 index
    ) external onlyOwner {
         _tracks[song][trackNum][index] = _tracks[song][trackNum][_tracks[song][trackNum].length - 1];
         _tracks[song][trackNum].pop();
    }

    function resetVariableTracks(
        SongID song,
        TrackID trackNum
    )
        external
        onlyOwner
    {
        delete _tracks[song][trackNum];
    }

    function addStaticTrack(SongID song, bytes calldata track)
        external
        onlyOwner
    {
        address pointer = SSTORE2.write(track);
        _staticTracks[song].push(pointer);
    }

    function removeStaticTrack(SongID song, uint256 index)
        external
        onlyOwner
    {
        _staticTracks[song][index] = _staticTracks[song][_staticTracks[song].length - 1];
        _staticTracks[song].pop();
    }

    function resetStaticTracks(SongID song) external onlyOwner {
        delete _staticTracks[song];
    }

    function setTimeDivision(SongID song, bytes2 timeDivision)
        public
        onlyOwner
    {
        _timeDivisions[song] = timeDivision;
    }

    // ERC-721 FUNCTIONS ---------------------------------------------------

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) {
            revert URIQueryForNonexistentToken();
        }
        bytes32 seed = _seeds[tokenId];

        SongID song = SongID.wrap(uint8(seed[0]));

        string memory mid = midi(tokenId);

        bytes memory json = abi.encodePacked(
            '{"name":"',
            _singular,
            " #",
            tokenId.toString(),
            '", "description": "',
            description,
            '", "image": "',
            baseURI,
            "/image/",
            uint256(seed).toHexString(),
            '", "animation_url": "',
            baseURI,
            "/animation/",
            uint256(seed).toHexString()
        );
        json = abi.encodePacked(
            json,
            '", "midi": "data:audio/midi;base64,',
            mid,
            '", "external_url": "https://beatfoundry.xyz", "composer": "',
            composer,
            '", "attributes": [{"trait_type": "Song", "value": '
        );
        if (bytes(_songNames[song]).length > 0) {
            json = abi.encodePacked(json, '"', _songNames[song], '"}');
        } else {
            json = abi.encodePacked(json, '"',SongID.unwrap(song).toString(), '"}');
        }

        json = abi.encodePacked(
            json,
            ', {"trait_type": "Cover", "value": "',
            _variants[tokenId].toString(),
            '"}'
        );
        
        for (uint256 i = 0; i < numVariableTracks; i++) {
            json = abi.encodePacked(
                json,
                ', {"trait_type": "Stem ',
                (i + 1).toString(),
                '", "value": "',
                uint256(uint8(seed[i + 1])).toString(),
                '"}'
            );
        }
        json = abi.encodePacked(json, "]}");
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(json)
                )
            );
    }

    function midi(uint256 tokenId) public view returns (string memory) {
        if (!_exists(tokenId)) {
            revert URIQueryForNonexistentToken();
        }
        bytes32 seed = _seeds[tokenId];

        SongID song = SongID.wrap(uint8(seed[0]));

        bytes memory mid = newMidi(6, song);

        uint256 lenStatic = _staticTracks[song].length;

        for (uint256 i = 0; i < numVariableTracks; i++) {
            bytes memory track = SSTORE2.read(
                _tracks[song][TrackID.wrap(i)][uint8(seed[i + 1])]
            );
            mid = bytes.concat(mid, newTrack(track));
        }

        for (uint256 i = 0; i < lenStatic; i++) {
            bytes memory track = SSTORE2.read(_staticTracks[song][i]);
            mid = bytes.concat(mid, newTrack(track));
        }

        return Base64.encode(mid);
    }

    function getSeedTokenID(bytes32 seed) public view returns (uint256) {
        return _seedTokenID[seed];
    }

    function getVariant(uint256 tokenId) public view returns (uint256) {
        if (!_exists(tokenId)) {
            revert URIQueryForNonexistentToken();
        }
        return _variants[tokenId];
    }

    // MINTING FUNCTIONS ---------------------------------------------------

    function mint(
        address to,
        bytes32 seed,
        uint256 variant,
        bytes calldata pass,
        bytes32[] calldata seedProof
    ) external payable onlyPhase(Phase.PUBLIC) mustPrice(mintPrice) {
      
        if (_currentIndex >= maxSupply) {
            revert MintingLimitReached();
        }

        if (_seedUsed[seed]) {
            revert SeedAlreadyUsed();
        } 

        if (!isValidSeedPassCombo(seed, variant, pass, seedProof)) {
            revert InvalidProof();
        }
        _seeds[_currentIndex] = seed;
        _variants[_currentIndex] = variant;
        _seedTokenID[seed] = _currentIndex;
        _seedUsed[seed] = true; 

        _mint(to, 1, bytes(""), true);
    }

    function mintReserve(address to, bytes32[] calldata seeds, uint256[] calldata variants)
        external
        virtual
        onlyOwner
        onlyPhase(Phase.RESERVE)
    {
        if (_currentIndex >= maxSupply) {
            revert MintingLimitReached();
        }
        if (seeds.length != variants.length) {
            revert SameLengthRequired();
        }
        for (uint256 i = 0; i < seeds.length; i++) {
            bytes32 seed = seeds[i];
            if (_seedUsed[seed]) {
                revert SeedAlreadyUsed();
            }
            _seeds[_currentIndex + i] = seed;
             _seedTokenID[seed] = _currentIndex + i;
            _seedUsed[seed] = true;
        }
        _mint(to, seeds.length, bytes(""), true);
    }

    function mintAllowlist(
        address to,
        bytes32[] calldata seeds,
        uint256[] calldata variants,
        bytes32[][] calldata allowlistProofs
    )
        external
        payable
        onlyPhase(Phase.ALLOWLIST)
        mustPrice(mintPrice * seeds.length)
    {
        if (_currentIndex >= maxSupply) {
            revert MintingLimitReached();
        }
        if (seeds.length != allowlistProofs.length || seeds.length != variants.length) {
            revert SameLengthRequired();
        }
        for (uint256 i = 0; i < seeds.length; i++) {
            bytes32 seed = seeds[i];
            if (!isAllowlistedFor(to, seed, variants[i], allowlistProofs[i])) {
                revert NotAllowlisted();
            }
            if (_seedUsed[seed]) {
                revert SeedAlreadyUsed();
            }
            _seeds[_currentIndex + i] = seed;
            _seedTokenID[seed] = _currentIndex + i;
            _variants[_currentIndex + i] = variants[i];
            _seedUsed[seed] = true;
        }

        _mint(to, seeds.length, bytes(""), true);
    }

    // MIDI FUNCTIONS ---------------------------------------------------

    function newMidi(uint8 numTracks, SongID song)
        private
        view
        returns (bytes memory)
    {
        bytes2 timeDivision = _timeDivisions[song];
        if (uint16(timeDivision) == 0) {
            timeDivision = bytes2(uint16(256));
        }
        bytes memory data = new bytes(14);
        data[0] = bytes1(0x4D);
        data[1] = bytes1(0x54);
        data[2] = bytes1(0x68);
        data[3] = bytes1(0x64);
        data[4] = bytes1(0x00);
        data[5] = bytes1(0x00);
        data[6] = bytes1(0x00);
        data[7] = bytes1(0x06);
        data[8] = bytes1(0x00);
        if (numTracks == 1) {
            data[9] = bytes1(0x00);
        } else {
            data[9] = bytes1(0x01);
        }
        data[10] = bytes1(0x00);
        data[11] = bytes1(numTracks);
        data[12] = timeDivision[0];
        data[13] = timeDivision[1];
        return data;
    }

    function newTrack(bytes memory data) private pure returns (bytes memory) {
        bytes memory it = new bytes(8);
        it[0] = bytes1(0x4D);
        it[1] = bytes1(0x54);
        it[2] = bytes1(0x72);
        it[3] = bytes1(0x6b);
        bytes memory asBytes = abi.encodePacked(data.length);
        it[4] = asBytes[asBytes.length - 4];
        it[5] = asBytes[asBytes.length - 3];
        it[6] = asBytes[asBytes.length - 2];
        it[7] = asBytes[asBytes.length - 1];
        return bytes.concat(it, data);
    }

    // ROYALTIES ---------------------------------------------------------------
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return (address(royaltyContract), (_salePrice / 100) * royaltyPercent);
    }

    // HELPERS ------------------------------------------------------------------

    function isAllowlistedFor(
        address _allowlistee,
        bytes32 _seed,
        uint256 _variant,
        bytes32[] calldata _proof
    ) private view returns (bool) {
        return
            MerkleProof.verify(
                _proof,
                _allowlistMerkleRoot,
                keccak256(abi.encodePacked(_allowlistee, _seed, _variant))
            );
    }

    function isValidSeedPassCombo(
        bytes32 _seed,
        uint256 _variant,
        bytes calldata _pass,
        bytes32[] calldata _proof
    ) private view returns (bool) {
        return
            MerkleProof.verify(
                _proof,
                _allSeedsMerkleRoot,
                keccak256(abi.encodePacked(keccak256(_pass), _seed, _variant))
            );
    }
}