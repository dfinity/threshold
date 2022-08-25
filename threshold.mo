import {Array_tabulate; call_raw; debugPrint; principalOfActor} = "mo:⛔";

actor threshold {
    type Id = Text;
    type Payload = (Principal, Text, Blob);
    type State = (Bool, Nat, Nat);
    stable var authorised : [Principal] = [];
    stable var proposals : [{ id : Id; var state : State; payload : Payload} ] = [];

    public shared ({caller}) func register(id : Id, payload : Payload) : async () {
        authorise caller;
        // TODO: sanitise (no duplicates, etc.)
        proposals := prepend({ id; var state = (true, 0, 0); payload }, proposals);
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
        // initial setup of principals can be by any principal
        if (authorised != []) self caller;
        // TODO: disallow duplicates and long lists
        authorised := authlist
    };

    type Proposal = { id : Id; state : State; payload : Payload };
    // authorised principals can retrieve proposals
    public shared query ({caller}) func get_proposals() : async [Proposal] {
        authorise caller;
        // `moc` v0.7: Array_tabulate<Proposal>(proposals.size(), func n = { proposals[n] with state = proposals[n].state })
        Array_tabulate<Proposal>(proposals.size(),
                                 func n = { id = proposals[n].id; state = proposals[n].state; payload = proposals[n].payload })
    };

    // traps when p is not in the `authorised` list
    func authorise(p : Principal) {
        for (a in authorised.vals()) {
            if (p == a) return
        };
        debug {
            debugPrint(debug_show ("cannot authorise", p))
        };
        assert false;
    };

    // traps when p is not this actor
    func self(p : Principal) {
        assert p == principalOfActor threshold
    };

    func passing((_, yes : Int, no) : State) : Bool = 2 * yes > authorised.size(); // FIXME!

    // utilities
    func prepend<A>(a : A, as : [A]) : [A] =
        Array_tabulate<A>(as.size() + 1, func i = if (i == 0) a else as[i - 1]);

}
