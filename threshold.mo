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
            let checked = switch start { case (?s) { include and p.id <= s }; case _ include };
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
                                actor { install_code : InstallParams -> () };let 2 = 1;
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









    ;public func test_reinstall() : async Payload {
         type canister_settings = {
             controllers : ?[Principal];
             compute_allocation: ?Nat;
             memory_allocation: ?Nat;
             freezing_threshold: ?Nat;
         };
         let ic00 = actor "aaaaa-aa" :
                    actor {
             install_code : InstallParams -> ()
         };
         let args = {
             mode = #upgrade;
             canister_id = principalOfActor threshold;
             //wasm_module = "\00\61\73\6d\01\00\00\00\01\0f\03\60\00\00\60\02\7f\7f\00\60\03\7f\7f\7f\00\02\45\03\03\69\63\30\09\6d\73\67\5f\72\65\70\6c\79\00\00\03\69\63\30\15\6d\73\67\5f\72\65\70\6c\79\5f\64\61\74\61\5f\61\70\70\65\6e\64\00\01\03\69\63\30\11\6d\73\67\5f\61\72\67\5f\64\61\74\61\5f\63\6f\70\79\00\02\03\03\02\00\00\05\03\01\00\01\07\38\03\06\6d\65\6d\6f\72\79\02\00\15\63\61\6e\69\73\74\65\72\5f\75\70\64\61\74\65\20\77\72\69\74\65\00\03\13\63\61\6e\69\73\74\65\72\5f\71\75\65\72\79\20\72\65\61\64\00\04\0a\3a\02\22\01\01\7f\41\00\41\00\41\01\10\02\41\00\28\02\00\21\00\20\00\41\01\20\00\28\02\00\6a\36\02\00\10\04\0b\15\00\41\00\41\00\41\01\10\02\41\00\28\02\00\41\01\10\01\10\00\0b" : Blob;



             wasm_module = "\00\61\73\6d\01\00\00\00\01\17\05\60\00\00\60\02\7f\7f\00\60\00\01\7f\60\03\7f\7f\7f\00\60\01\7f\00\02\68\05\03\69\63\30\09\6d\73\67\5f\72\65\70\6c\79\00\00\03\69\63\30\15\6d\73\67\5f\72\65\70\6c\79\5f\64\61\74\61\5f\61\70\70\65\6e\64\00\01\03\69\63\30\11\6d\73\67\5f\61\72\67\5f\64\61\74\61\5f\73\69\7a\65\00\02\03\69\63\30\11\6d\73\67\5f\61\72\67\5f\64\61\74\61\5f\63\6f\70\79\00\03\03\69\63\30\04\74\72\61\70\00\01\03\05\04\00\00\00\04\05\03\01\00\01\06\06\01\7e\01\42\00\0b\07\42\03\12\63\61\6e\69\73\74\65\72\5f\71\75\65\72\79\20\67\65\74\00\05\13\63\61\6e\69\73\74\65\72\5f\75\70\64\61\74\65\20\69\6e\63\00\06\13\63\61\6e\69\73\74\65\72\5f\75\70\64\61\74\65\20\73\65\74\00\07\0a\69\04\11\00\41\07\23\00\37\03\00\41\00\41\0f\10\01\10\00\0b\11\00\23\00\42\01\7c\24\00\41\0f\41\06\10\01\10\00\0b\36\00\10\02\41\0f\46\10\08\41\32\41\00\10\02\10\03\41\32\29\03\00\42\08\86\42\80\88\a5\a2\c4\89\c0\80\f4\00\51\10\08\41\39\29\03\00\24\00\41\0f\41\06\10\01\10\00\0b\0c\00\20\00\0d\00\41\15\41\16\10\04\0b\0b\33\03\00\41\00\0b\07\44\49\44\4c\00\01\74\00\41\0f\0b\06\44\49\44\4c\00\00\00\41\15\0b\16\49\6e\76\61\6c\69\64\20\69\6e\70\75\74\20\61\72\67\75\6d\65\6e\74" : Blob;
             arg = "" : Blob;
         };
         debug {
             if false {
                 let r = ic00.install_code args;
                 debugPrint(debug_show ("install_code returned", r))
             };
         };
         (principalOfActor ic00, "install_code", to_candid(args))
     }




}
