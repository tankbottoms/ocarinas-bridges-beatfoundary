// SPDX-License-Identifier: MIT

import "./Address.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./ERC721.sol";
import "./Base64.sol";

pragma solidity ^0.8.0;

contract Ocarinas is ERC721, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;
    using Address for address payable;

    struct Slice {
        uint256 start;
        uint256 length;
    }

    uint256 public numChordProgressions;
    uint256 public mintPrice;
    uint256 public totalSupply;
    uint256 private _royaltyDivisor = 20;
    // Melodies and drums are mappings of chord progression number => array of tracks
    // a track being an array of bytes representing the MIDI data.
    // Bass and chords do not have multiple variations per chord progression and therefore is just
    // a single track.
    mapping(uint256 => bytes[]) private _firstMelodyParts;
    mapping(uint256 => bytes[]) private _secondMelodyParts;
    mapping(uint256 => bytes[]) private _thirdMelodyParts;
    mapping(uint256 => bytes[]) private _drums;
    mapping(uint256 => bytes) private _bass;
    mapping(uint256 => bytes) private _chords;
    mapping(uint256 => bytes2) private _timeDivisions;

    bool public mintingEnabled;

    bytes32 private _allSeedsMerkleRoot;

    mapping(uint256 => bytes5) private _seeds;
    mapping(bytes5 => bool) private _seedUsed;

    Counters.Counter private _tokenIdTracker;

    string private baseURI;

    string public composer = "Shaw Avery @ShawAverySongs";

    // CONSTRUCTOR ---------------------------------------------------

    constructor(
        string memory baseURI_,
        uint256 numChordProgressions_,
        uint256 mintPrice_
    ) ERC721("Ocarinas", "OC") {
        baseURI = baseURI_;
        numChordProgressions = numChordProgressions_;
        mintPrice = mintPrice_;
    }

    // ADMIN FUNCTIONS ---------------------------------------------------

    function setBaseURI(string memory baseURI_) public onlyOwner {
        baseURI = baseURI_;
    }

    function setMintingEnabled(bool value, uint256 supply) public onlyOwner {
        mintingEnabled = value;
        totalSupply = supply;
    }

    function setMintPrice(uint256 value) public onlyOwner {
        mintPrice = value;
    }

    function setComposer(string memory _composer) public onlyOwner {
        composer = _composer;
    }

    function setRoyaltyDivisor(uint256 value) public onlyOwner {
        _royaltyDivisor = value;
    }

    function setNumChordProgressions(uint256 value) public onlyOwner {
        numChordProgressions = value;
    }

    function setAllSeedsMerkleRoot(bytes32 value) public onlyOwner {
        _allSeedsMerkleRoot = value;
    }

    function withdraw(address payable to, uint256 amount) public onlyOwner {
        require(
            address(this).balance >= amount,
            "Ocarinas: Insufficient balance to withdraw"
        );
        if (amount == 0) {
            amount = address(this).balance;
        }
        if (to == address(0)) {
            to = payable(owner());
        }
        to.sendValue(amount);
    }

    function addFirstMelodyPart(uint256 chordProgessions, bytes calldata melody)
        external
        onlyOwner
    {
        _firstMelodyParts[chordProgessions].push(melody);
    }

    function removeFirstMelodyPart(uint256 chordProgessions, uint256 index)
        external
        onlyOwner
    {
        _firstMelodyParts[chordProgessions][index] = _firstMelodyParts[
            chordProgessions
        ][_firstMelodyParts[chordProgessions].length - 1];
        _firstMelodyParts[chordProgessions].pop();
    }

    function addSecondMelodyPart(uint256 chordProgessions, bytes calldata bass)
        external
        onlyOwner
    {
        _secondMelodyParts[chordProgessions].push(bass);
    }

    function removeSecondMelodyPart(uint256 chordProgessions, uint256 index)
        external
        onlyOwner
    {
        _secondMelodyParts[chordProgessions][index] = _secondMelodyParts[
            chordProgessions
        ][_secondMelodyParts[chordProgessions].length - 1];
        _secondMelodyParts[chordProgessions].pop();
    }

    function addThirdMelodyPart(uint256 chordProgessions, bytes calldata solo)
        external
        onlyOwner
    {
        _thirdMelodyParts[chordProgessions].push(solo);
    }

    function removeThirdMelodyPart(uint256 chordProgessions, uint256 index)
        external
        onlyOwner
    {
        _thirdMelodyParts[chordProgessions][index] = _thirdMelodyParts[
            chordProgessions
        ][_thirdMelodyParts[chordProgessions].length - 1];
        _thirdMelodyParts[chordProgessions].pop();
    }

    function addDrums(uint256 chordProgessions, bytes calldata drums)
        external
        onlyOwner
    {
        _drums[chordProgessions].push(drums);
    }

    function removeDrums(uint256 chordProgessions, uint256 index)
        external
        onlyOwner
    {
        _drums[chordProgessions][index] = _drums[chordProgessions][
            _drums[chordProgessions].length - 1
        ];
        _drums[chordProgessions].pop();
    }

    function setBass(uint256 chordProgessions, bytes calldata bass)
        external
        onlyOwner
    {
        _bass[chordProgessions] = bass;
    }

    function setChords(uint256 chordProgessions, bytes calldata chords)
        external
        onlyOwner
    {
        _chords[chordProgessions] = chords;
    }

    function setTimeDivision(uint256 chordProgessions, bytes2 timeDivision)
        external
        onlyOwner
    {
        _timeDivisions[chordProgessions] = timeDivision;
    }

    // ERC-721 FUNCTIONS ---------------------------------------------------

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Ocarinas: nonexistent token");
        bytes5 seed = _seeds[tokenId];

        string memory mid = Base64.encode(
            bytes.concat(
                newMidi(6, uint8(seed[0])),
                newTrack(_firstMelodyParts[uint8(seed[0])][uint8(seed[1])]),
                newTrack(_secondMelodyParts[uint8(seed[0])][uint8(seed[2])]),
                newTrack(_thirdMelodyParts[uint8(seed[0])][uint8(seed[3])]),
                newTrack(_drums[uint8(seed[0])][uint8(seed[4])]),
                newTrack(_bass[uint8(seed[0])]),
                newTrack(_chords[uint8(seed[0])])
            )
        );

        bytes memory json = abi.encodePacked(
            '{"name": "Ocarina #',
            tokenId.toString(),
            '", "description": "A unique piece of music represented entirely on-chain in the MIDI format with inspiration from the musical themes and motifs of video games.", "image": "',
            baseURI,
            "/image/",
            uint256(uint40(seed)).toHexString(),
            '", "animation_url": "',
            baseURI
        );
        json = abi.encodePacked(
            json,
            "/animation/",
            uint256(uint40(seed)).toHexString(),
            '", "audio": "data:audio/midi;base64,',
            mid,
            '", "external_url": "http://beatfoundry.xyz", "attributes": [{"trait_type": "Chord Progression", "value": "',
            uint256(uint8(seed[0]) + 1).toString(),
            '"}, {"trait_type": "First Melody", "value": "',
            uint256(uint8(seed[1]) + 1).toString(),
            '"}, {"trait_type": "Second Melody", "value": "'
        );
        json = abi.encodePacked(
            json,
            uint256(uint8(seed[2]) + 1).toString(),
            '"}, {"trait_type": "Third Melody", "value": "',
            uint256(uint8(seed[3]) + 1).toString(),
            '"}, {"trait_type": "Drums", "value": "',
            uint256(uint8(seed[4]) + 1).toString(),
            '"}], "composer": "',
            composer,
            '"}'
        );
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(json)
                )
            );
    }

    function midi(uint256 tokenId)
        external
        view
        virtual
        returns (string memory)
    {
        require(_exists(tokenId), "Ocarinas: nonexistent token");
        bytes5 seed = _seeds[tokenId];
        bytes memory drums = newTrack(_drums[uint8(seed[0])][uint8(seed[4])]);
        bytes memory fmp = newTrack(
            _firstMelodyParts[uint8(seed[0])][uint8(seed[1])]
        );
        bytes memory smp = newTrack(
            _secondMelodyParts[uint8(seed[0])][uint8(seed[2])]
        );
        bytes memory tmp = newTrack(
            _thirdMelodyParts[uint8(seed[0])][uint8(seed[3])]
        );
        bytes memory bass = newTrack(_bass[uint8(seed[0])]);
        bytes memory chords = newTrack(_chords[uint8(seed[0])]);

        bytes memory mid = bytes.concat(
            newMidi(6, uint8(seed[0])),
            fmp,
            smp,
            tmp,
            drums,
            bass,
            chords
        );

        string memory output = string(Base64.encode(mid));
        return output;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    // MINTING FUNCTIONS ---------------------------------------------------

    function mint(
        address to,
        bytes5 seed,
        bytes calldata pass,
        bytes32[] calldata seedProof
    ) external payable virtual {
        require(mintingEnabled, "Ocarinas: minting disabled");
        require(msg.value == mintPrice, "Ocarinas: incorrect minting price");
        uint256 tokenID = _tokenIdTracker.current();

        require(tokenID < totalSupply, "Ocarinas: minting limit reached");
        require(!_seedUsed[seed], "Ocarinas: seed already used");

        bytes32 hashedPass = keccak256(pass);
        require(
            MerkleProof.verify(
                seedProof,
                _allSeedsMerkleRoot,
                keccak256(abi.encodePacked(hashedPass, seed))
            ),
            "Ocarinas: invalid seed proof"
        );

        _seeds[tokenID] = seed;
        _seedUsed[seed] = true;

        _mint(to, tokenID);
        _tokenIdTracker.increment();
    }

    // MIDI FUNCTIONS ---------------------------------------------------

    function newMidi(uint8 numTracks, uint8 chordProgression)
        internal
        view
        returns (bytes memory)
    {
        bytes2 timeDivision = _timeDivisions[chordProgression];
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

    function newTrack(bytes memory data) internal pure returns (bytes memory) {
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

    // EXTRA FUNCTIONS ---------------------------------------------------

    function usedSupply() external view returns (uint256) {
        return _tokenIdTracker.current();
    }
}