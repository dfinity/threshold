import {call_raw; principalOfActor} "mo:⛔";

actor threshold {
    type Id = Text;
    type Payload = (Principal, Text, Blob);
    type State = (Bool, Nat, Nat);
    stable var authorised : [Principal] = [];
    stable var proposals : [{ id : Id; var state : State; payload : Payload} ] = [];

    public func register(id : Id, payload : Payload) : async () {
        // TODO allow several
        proposals := [{ id; var state = (false, 0, 0); payload }];
    };

    public shared ({caller}) func accept(id : Id) : async () {
        authorise caller;
        for (prop in proposals.vals()) {
            let { id = i; payload = (principal, method, blob) } = prop;
            let (active, yes, no) = prop.state;
            if (id != i or not active) return;
            prop.state := (active, yes + 1, no); // FIXME: track votes by principal
            if (passing(prop.state)) {
                prop.state := (false, prop.state.1, prop.state.2);
                // send the payload
                let _ = call_raw(principal, method, blob);
            }
        };
    };

    public shared ({caller}) func reject(id : Id) : async () {
        authorise caller;
        for (prop in proposals.vals()) {
            let { id = i; payload = (principal, method, blob) } = prop;
            let (active, yes, no) = prop.state;
            if (id != i or not active) return;
            prop.state := (active, yes, no + 1); // FIXME: track votes by principal
        }
    };

    public shared ({caller}) func update(authlist : [Principal]) : async () {
        if (authlist != []) self caller;
        // TODO: disallow duplicates and long lists
        authorised := authlist
    };

    // traps when p is not in the `authorised` list
    func authorise(p : Principal) {
        for (a in authorised.vals()) {
            if (p == a) return
        };
        assert false;
    };

    // traps when p is not this actor
    func self(p : Principal) {
        if (p == principalOfActor threshold) return;
        assert false;
    };

    func passing((_, yes : Int, no) : State) : Bool = yes - no > 3; // FIXME!

}
