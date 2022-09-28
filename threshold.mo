import {Array_tabulate; Array_init; call_raw; debugPrint; principalOfActor; nat64ToNat; time = nanos1970} = "mo:⛔";

actor class(signers : [Principal]) = threshold {
    type Id = Nat;
    type Timestamp = Nat;
    type Payload = (Principal, Text, Blob);
    type Vote = (Timestamp, Principal);
    type State = { active : Bool; yes : Nat; no : Nat; votes : [Vote]; result : ?Blob };
    type Prop = { id : Id; memo : Text; signers : [Principal]; var state : State; payload : Payload };

    // criterion for valid signers
    func sanitiseSigners(signers : [Principal]) : [Principal] {
        assert signers.size() > 1;
        // no duplicates allowed
        let good = Array_init<?Principal>(signers.size(), null);
        var occup = 0;
        for (s0 in signers.vals()) {
            let s = ?s0;
            var j = 0;
            while (j < occup) {
                assert s != good[j];
                j += 1
            };
            good[occup] := s;
            occup += 1
        };
        signers
    };

    stable var serial = 0;
    stable var authorised : [Principal] = sanitiseSigners signers;
    stable var proposals : [Prop] = [];

    public shared ({caller}) func submit(memo : Text, payload : Payload) : async Nat {
        authorise caller;
        serial += 1;
        let ?votes = vote(caller, []);
        let state = { active = true; yes = 1; no = 0; votes; result = null };
        proposals := prepend<Prop>({ id = serial; memo; signers = authorised; var state; payload }, proposals);
        serial
    };

    public shared ({caller}) func accept(id : Id) : async () {
        for (prop in proposals.vals()) {
            let { id = i; payload; signers } = prop;
            if (id == i) {
                authoriseAccording(caller, signers);
                let { active; yes; votes } = prop.state;
                switch (active, vote(caller, votes)) {
                    case (true, ?votes) {
                        prop.state := { prop.state with yes = yes + 1; votes };
                        func passing( { yes } : State) : Bool = 2 * yes > signers.size();
                        if (passing(prop.state)) {
                            // retire the proposal
                            prop.state := { prop.state with active = false };
                            // execute payload and keep result in the state
                            await execute(prop, payload)
                        };
                        return
                    };
                    case _ ()
                }
            }
        }
    };

    public shared ({caller}) func reject(id : Id) : async () {
        for (prop in proposals.vals()) {
            let { id = i; signers } = prop;
            if (id == i) {
                authoriseAccording(caller, signers);
                let { active; no; votes } = prop.state;
                switch (active, vote(caller, votes)) {
                    case (true, ?votes) {
                        let state = { prop.state with no = no + 1; votes };
                        func hopeless({ no } : State) : Bool = 2 * no >= signers.size();
                        prop.state := { state with active = not hopeless state };
                        return
                    };
                    case _ ()
                }
            }
        }
    };

    public shared ({caller}) func prune() : async () {
        self caller;
        proposals := filter(func (p : Prop) : Bool = p.state.active, proposals)
    };

    public shared ({caller}) func set_signers(authlist : [Principal]) : async () {
        self caller;
        authorised := sanitiseSigners authlist
    };

    public shared ({caller}) func get_signers() : async [Principal] {
        authorise caller;
        authorised
    };

    type Proposal = { id : Id; memo : Text; state : State; payload : Payload };
    // authorised principals can retrieve proposals (in reverse creation order)
    // `start` (when given) specifies the newest proposal the caller is interested in
    // `count` (when given) specifies the number of proposals returned (defaults to 10)
    public shared ({caller}) func get_proposals({ start : ?Id; count : ?Nat }) : async [Proposal] {
        let defaultCount = 10;
        authorise caller;
        let all = Array_tabulate<Proposal>(proposals.size(), func n = { proposals[n] with state = proposals[n].state });
        var toGo : Int = switch count { case null defaultCount; case (?c) c };
        func onPage(p : Proposal) : Bool {
            let include = toGo > 0;
            let checked = switch start { case (?s) { include and p.id >= s }; case _ include };
            if checked { toGo -= 1 };
            checked
        };
        filter(onPage, all)
    };

    public shared ({caller}) func get_proposal(id : Id) : async ?Proposal {
        for (p in proposals.vals()) {
            if (p.id == id) {
                authoriseAccording(caller, p.signers);
                return ?{ p with state = p.state }
            }
        };
        null
    };

    // traps when p is not in the given principals list
    func authoriseAccording(p : Principal, according : [Principal]) {
        for (a in according.vals()) {
            if (p == a) return
        };
        debug {
            debugPrint(debug_show ("cannot authorise", p))
        };
        assert false;
    };

    // traps when p is not in the `authorised` list
    func authorise(p : Principal) = authoriseAccording(p, authorised);

    // traps when p is not this actor
    func self(p : Principal) {
        assert p == principalOfActor threshold
    };

    // internal helper
    private func execute(prop : Prop, (principal, method, blob) : Payload) : async () {
        // send the payload
        switch (is_selfupgrade(principal, method, blob)) {
            case (?params) {
                     debug debugPrint(debug_show ("it's a selfupgrade", params));
                     let ic00 = actor "aaaaa-aa" :
                                actor { install_code : InstallParams -> () };
                     ic00.install_code params
                 };
            case _ {
                let res = await call_raw(principal, method, blob);
                prop.state := { prop.state with result = ?res };
            }
        }
    };

    // utilities
    func prepend<A>(a : A, as : [A]) : [A] =
        Array_tabulate<A>(as.size() + 1, func i = if (i == 0) a else as[i - 1]);

    func filter<A>(p : A -> Bool, as : [A]) : [A] {
        var hits = 0;
        let good = Array_init<?A>(as.size(), null);
        for (a in as.vals()) {
            if (p(a)) { good[hits] := ?a; hits += 1 };
        };
        Array_tabulate<A>(hits, func(i) : A { let ?h = good[i]; h });
    };

    // helpers
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
