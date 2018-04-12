pragma solidity 0.4.19;


contract StateMachine {

    //Struct to hold elements of transition
    struct Transitions {
        function() internal[] transitionEffects; 
        function(bytes32) internal returns(bool)[] startConditions; 
        bool transitionExists; //Probably not needed...
    }

    //Mapping of each transition id to info. 
    mapping(bytes32 => Transitions) transitions;

    //Struct to hold elements of each state
    struct States {
        bytes32[] nextStates;
        mapping(bytes4=>bool) allowedFunctions; 
    }

    //Mapping of each state id to info. 
    mapping(bytes32 => States) states; 

    // The current state id
    bytes32 public currentStateId;

    // after the first transition in the state machine has occurred, it is immutable
    // therefore set up must be complete by this time
    bool machineImmutable;

    event LogTransition(bytes32 stateId, uint256 blockNumber);

    /* This modifier performs the conditional transitions and checks that the function 
     * to be executed is allowed in the current State
     */
    modifier checkAllowed {
        conditionalTransitions();
        require(states[currentStateId].allowedFunctions[msg.sig]);
        _;
    }

    // This is to ensure that after the state machine has been set up it cannot be changed
    modifier stillSettingUp {
        require(!machineImmutable);
        _;
    }

    function setInitialState(bytes32 _initialState) internal {
        require (currentStateId == 0);
        require (_initialState != 0);
        currentStateId = _initialState;
    }

    /// @dev returns the id of the transition between 2 states.
    /// @param _fromStateId The id of the start state of the transition.
    /// @param _toStateId The id of the end state of the transition.
    function getTransitionId(bytes32 _fromStateId, bytes32 _toStateId) public pure returns(bytes32) {
        require(_fromStateId != 0);
        require(_toStateId != 0);
        return keccak256(_fromStateId, _toStateId);
    }

    /// @dev Creates a transition in the state machine
    /// @param _fromStateId The id of the start state of the transition.
    /// @param _toStateId The id of the end state of the transition.
    function createTransition(bytes32 _fromStateId, bytes32 _toStateId) internal stillSettingUp {
        bytes32 transitionId = getTransitionId(_fromStateId, _toStateId);
        states[_fromStateId].nextStates.push(_toStateId);
        transitions[transitionId].transitionExists = true; 
    }

    /// @dev adds a condition that must be true for a transition to occur.
    /// @param _fromStateId The id of the start state of the transition.
    /// @param _toStateId The id of the end state of the transition.
    /// @param _startCondition The condition itself.
    function addStartCondition(bytes32 _fromStateId, bytes32 _toStateId, function(bytes32) internal returns(bool) _startCondition) internal stillSettingUp {
        bytes32 transitionId = getTransitionId(_fromStateId, _toStateId);
        require(transitions[transitionId].transitionExists);
        transitions[transitionId].startConditions.push(_startCondition);
    }

    /// @dev adds an effect that is performed when a transition occurs
    /// @param _fromStateId The id of the start state of the transition.
    /// @param _toStateId The id of the end state of the transition.
    /// @param _transitionEffect The effect itself.
    function addTransitionEffect(bytes32 _fromStateId, bytes32 _toStateId, function() internal _transitionEffect) internal stillSettingUp {
        bytes32 transitionId = getTransitionId(_fromStateId, _toStateId);
        require(transitions[transitionId].transitionExists);
        transitions[transitionId].transitionEffects.push(_transitionEffect);
    }

    /// @dev Allow a function in the given state.
    /// @param _stateId The id of the state
    /// @param _functionSelector A function selector (bytes4[keccak256(functionSignature)])
    function allowFunction(bytes32 _stateId, bytes4 _functionSelector) internal stillSettingUp {
        states[_stateId].allowedFunctions[_functionSelector] = true;
    }

    /// @dev Goes to the next state if possible (if the next state is valid and reachable by a transition from the current state)
    /// @param _nextStateId stateId of the state to transition to
    function goToNextState(bytes32 _nextStateId) internal {
        bytes32 transitionId = getTransitionId(currentStateId, _nextStateId);
        require(transitions[transitionId].transitionExists);
        function() internal[] theEffects = transitions[transitionId].transitionEffects;
        for (uint256 i = 0; i < theEffects.length; i++) {
            theEffects[i]();
        }
        currentStateId = _nextStateId;
        if (!machineImmutable) {
            machineImmutable = true;
        }
        LogTransition(_nextStateId, block.number);
    }


    ///@dev transitions the state machine into the state it should currently be in
    ///@dev by taking into account the current conditions and how many further transitions can occur 
    function conditionalTransitions() internal {

        bytes32[] storage outgoing = states[currentStateId].nextStates;

        while (outgoing.length > 0) {
            bool stateChanged = false;
            //consider each of the next states in turn
            for (uint256 j = 0; j < outgoing.length; j++) {
                //Get the state that you are now to consider
                bytes32 nextState = outgoing[j];
                bytes32 transitionId = getTransitionId(currentStateId, nextState);
                // If this state's start condition is met, go to this state and continue
                function(bytes32) internal returns(bool)[] startConds = transitions[transitionId].startConditions;
                for (uint256 i = 0; i < startConds.length; i++) {
                    if (startConds[i](nextState)) {
                        goToNextState(nextState);
                        stateChanged = true;
                        outgoing = states[currentStateId].nextStates;
                        break;
                    }
                }
                if (stateChanged) break;
            }
            //If we've tried all the possible following states and not changed, we're in the right state now
            if (!stateChanged) break;
        }
    }

}
