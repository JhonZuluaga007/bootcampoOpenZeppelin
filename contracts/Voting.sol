// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
contract Voting {
    // Variables de estado
    struct Voter{
        bool voted;
        bool canVote;
        // por quien voto
    }
    mapping(address => Voter) public voters;
    struct Candidate{
        string name;
        uint voteCount;
    }
    Candidate[2] public candidates;
    bool public isActive;
    address public admin;
    // Modificadores
    modifier onlyAdmin(){
        // validar que el sender sea el admin
        require(msg.sender== admin, "No eres el admin");
        _;
    }
    // Eventos
    // Constructor
    constructor(string memory _candidate1, string memory _candidate2){
        admin = msg.sender;
        isActive = true;
        candidates[0] = Candidate({
            name: _candidate1,
            voteCount: 0
        });
        candidates[1] = Candidate({
            name: _candidate2,
            voteCount: 0
        });
    }
    // Funciones
        // Funciones publicas
        // Funciones privadas
    // Funcion para votar
    function vote (uint _candidateToVote) public returns(bool){
        // validar si la votacion estÃ¡ activa
        require(isActive, "La votacion ya cerro");
        // instanciamos al votante
        Voter storage sender =  voters[msg.sender];
        // si tienes derecho a votar
        require(sender.canVote,"No tienes derecho a votar");
        // si ya voto
        require(!sender.voted,"No tienes derecho a votar");
        // que vote por un candidato valido
        require(_candidateToVote<2, "Invalid candidate");
        // Escribir el voto en candidatos
        candidates[_candidateToVote].voteCount ++;
        // actualizar votante
        sender.voted = true;
        return true;
    }
    // Funcion para otorgar derecho a votar
    function giveRightToVote(address _voter) public onlyAdmin {
        // que no haya votado
        require(!voters[_voter].voted, "Ya votaste");
        // actualizar al voter
        voters[_voter].canVote = true;
    }
    // Terminar la votacion
    function endVoteContract() public onlyAdmin {
        isActive = false;
    }
    // Obtener al ganador
    function getWinningName () public view  returns(string memory){
        require(!isActive, "La votacion sigue abierta");
        if(candidates[0].voteCount> candidates[1].voteCount){
            return candidates[0].name;
        } else{
            return candidates[1].name;
        }
    }
}