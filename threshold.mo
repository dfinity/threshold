import {Array_tabulate; call_raw; debugPrint; principalOfActor; nat64ToNat; time = nanos1970} = "mo:⛔";

actor threshold {
    type Id = Text;
    type Timestamp = Nat;
    type Payload = (Principal, Text, Blob);
    type Vote = (Timestamp, Principal);
    type State = (Bool, Nat, Nat, [Vote]);
    type Prop = { id : Id; var state : State; payload : Payload };

    stable var authorised : [Principal] = [];
    stable var proposals : [Prop] = [];

    public shared ({caller}) func register(id : Id, payload : Payload) : async () {
        authorise caller;
        // TODO: sanitise (no duplicates, etc.)
        let ?votes = vote(caller, []);
        proposals := prepend<Prop>({ id; var state = (true, 1, 0, votes); payload }, proposals);
    };

    public shared ({caller}) func accept(id : Id) : async () {
        authorise caller;
        for (prop in proposals.vals()) {
            let { id = i; payload = (principal, method, blob) } = prop;
            let (active, yes, no, votes) = prop.state;
            switch (vote(caller, votes)) {
                case null return;
                case (?votes) {
                    if (id == i and active) {
                        prop.state := (active, yes + 1, no, votes); // FIXME: track votes by principal
                        if (passing(prop.state)) {
                            prop.state := (false, prop.state.1, prop.state.2, prop.state.3);
                            // send the payload
                            switch (is_selfupgrade(principal, method, blob)) {
                                case (?params) {
                                    debug debugPrint(debug_show ("it's a selfupgrade", params));
                                    let ic00 = actor "aaaaa-aa" :
                                               actor { install_code : InstallParams -> () };
                                    ic00.install_code params
                                };
                                case _ {
                                    let _ = await call_raw(principal, method, blob)
                                }
                            }
                        };
                        return
                    }
                }
            }
        };
    };

    public shared ({caller}) func reject(id : Id) : async () {
        authorise caller;
        for (prop in proposals.vals()) {
            let { id = i; payload = (principal, method, blob) } = prop;
            let (active, yes, no, votes) = prop.state;
            if (id == i and active) {
                prop.state := (active, yes, no + 1, votes); // FIXME: track votes by principal
                return
            }
        }
    };

    public shared ({caller}) func update(authlist : [Principal]) : async () {
        // initial setup of principals can be by any principal
        if (authorised != []) self caller;
        // TODO: disallow duplicates and long lists
        authorised := authlist
    };

    public shared query ({caller}) func get_authorised() : async [Principal] {
        authorise caller;
        authorised
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

    func passing((_, yes : Int, no, _) : State) : Bool = 2 * yes > authorised.size(); // FIXME!

    // utilities
    func prepend<A>(a : A, as : [A]) : [A] =
        Array_tabulate<A>(as.size() + 1, func i = if (i == 0) a else as[i - 1]);

    type InstallParams = {
        mode : { #install; #reinstall; #upgrade };
        canister_id : Principal;
        wasm_module : Blob;
        arg : Blob;
    };
    func is_selfupgrade((addressee, method, args) : Payload) : ?InstallParams {
        if (addressee == principalOfActor (actor "aaaaa-aa") and method == "install_code") {
            do ? {
                let params : InstallParams = (from_candid(args) : ?InstallParams)!;
                if (params.canister_id == principalOfActor threshold)
                   params
                   else null!
            }
        } else null
    };

    func now() : Timestamp = nat64ToNat(nanos1970()) / 1_000_000_000; // seconds since 1970-01-01

    func vote(signer : Principal, votes : [Vote]) : ?[Vote] {
        for ((_, p) in votes.vals()) {
            if (p == signer) return null;
        };
        ?prepend((now(), signer), votes);
    }
}
