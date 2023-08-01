// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./Tournament.sol";
import "../../Commitment.sol";
import "../../Merkle.sol";

import "step/ready_src/UArchStep.sol";

/// @notice Leaf tournament is the one that seals leaf match
abstract contract LeafTournament is Tournament {
    using Machine for Machine.Hash;
    using Commitment for Tree.Node;
    using Tree for Tree.Node;
    using Clock for Clock.State;
    using Match for Match.Id;
    using Match for Match.State;

    constructor() {}

    function sealLeafMatch(
        Match.Id calldata _matchId,
        Tree.Node _leftLeaf,
        Tree.Node _rightLeaf,
        Machine.Hash _initialHash,
        bytes32[] calldata _initialHashProof
    ) external tournamentNotFinished {
        Match.State storage _matchState = matches[_matchId.hashFromId()];
        _matchState.requireExist();
        _matchState.requireCanBeFinalized();
        _matchState.requireParentHasChildren(_leftLeaf, _rightLeaf);

        Machine.Hash _finalStateOne;
        Machine.Hash _finalStateTwo;

        if (!_matchState.agreesOnLeftNode(_leftLeaf)) {
            // Divergence is in the left leaf!
            (_finalStateOne, _finalStateTwo) = _matchState
                .setDivergenceOnLeftLeaf(_leftLeaf);
        } else {
            // Divergence is in the right leaf!
            (_finalStateOne, _finalStateTwo) = _matchState
                .setDivergenceOnRightLeaf(_rightLeaf);
        }

        // Unpause clocks
        Clock.State storage _clock1 = clocks[_matchId.commitmentOne];
        Clock.State storage _clock2 = clocks[_matchId.commitmentTwo];
        _clock1.setPaused();
        _clock1.advanceClock();
        _clock2.setPaused();
        _clock2.advanceClock();

        // Prove initial hash is in commitment
        if (_matchState.runningLeafPosition == 0) {
            require(_initialHash.eq(initialHash), "initial hash incorrect");
        } else {
            _matchId.commitmentOne.proveHash(
                _matchState.runningLeafPosition - 1,
                _initialHash,
                _initialHashProof
            );
        }

        _matchState.setInitialState(_initialHash);
    }

    function winLeafMatch(
        Match.Id calldata _matchId,
        Tree.Node _leftNode,
        Tree.Node _rightNode,
        bytes calldata proofs
    ) external tournamentNotFinished {
        Match.State storage _matchState = matches[_matchId.hashFromId()];
        _matchState.requireExist();
        _matchState.requireIsFinished();

        Clock.State storage _clockOne = clocks[_matchId.commitmentOne];
        Clock.State storage _clockTwo = clocks[_matchId.commitmentTwo];
        _clockOne.requireInitialized();
        _clockTwo.requireInitialized();

        Machine.Hash _finalState = Machine.Hash.wrap(metaStep(
            _matchState.runningLeafPosition,
            AccessLogs.Context(
                Tree.Node.unwrap(_matchState.otherParent),
                Buffer.Context(proofs, 0)
            )
        ));

        (
            Machine.Hash _finalStateOne,
            Machine.Hash _finalStateTwo
        ) = _matchState.getDivergence();

        if (_leftNode.join(_rightNode).eq(_matchId.commitmentOne)) {
            require(
                _finalState.eq(_finalStateOne),
                "final state one doesn't match"
            );

            _clockOne.addValidatorEffort(Time.ZERO_DURATION);
            pairCommitment(
                _matchId.commitmentOne,
                _clockOne,
                _leftNode,
                _rightNode
            );
        } else if (_leftNode.join(_rightNode).eq(_matchId.commitmentTwo)) {
            require(
                _finalState.eq(_finalStateTwo),
                "final state two doesn't match"
            );

            _clockTwo.addValidatorEffort(Time.ZERO_DURATION);
            pairCommitment(
                _matchId.commitmentTwo,
                _clockTwo,
                _leftNode,
                _rightNode
            );
        } else {
            revert("wrong left/right nodes for step");
        }

        delete matches[_matchId.hashFromId()];
    }

    // TODO: move to step repo
    // TODO: add ureset
    function metaStep(uint256 counter, AccessLogs.Context memory accessLogs)
         internal
         pure
         returns (bytes32)
     {
         uint256 mask = (1 << 64) - 1;
         if (counter & mask == mask) {
             // reset
             revert("RESET UNIMPLEMENTED");
         } else {
             UArchStep.step(accessLogs);
             bytes32 machineState = accessLogs.currentRootHash;
             return machineState;
         }
     }
}