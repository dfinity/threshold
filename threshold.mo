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
            if (id == i and active) {
                prop.state := (active, yes + 1, no); // FIXME: track votes by principal
                if (passing(prop.state)) {
                    prop.state := (false, prop.state.1, prop.state.2);
                    // send the payload
                    switch (is_selfupgrade(principal, method, blob)) {
                      case (?params) {
                          debug debugPrint(debug_show ("it's a selfupgrade", params));
                          let ic00 = actor "aaaaa-aa" :
                                     actor {
                                               install_code : InstallParams -> ()
                                           };
                          ic00.install_code params
                      };
                      case _ {
                              let _ = await call_raw(principal, method, blob)
                          }
                      }
                };
                return
            }
        };
    };

    public shared ({caller}) func reject(id : Id) : async () {
        authorise caller;
        for (prop in proposals.vals()) {
            let { id = i; payload = (principal, method, blob) } = prop;
            let (active, yes, no) = prop.state;
            if (id == i and active) {
                prop.state := (active, yes, no + 1); // FIXME: track votes by principal
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

    // testing code
    public func test_payload_for_accept() : async Payload {
        let args : Id = "haha";
        if false { let _ = accept args };
        (principalOfActor threshold, "accept", to_candid(args))
    };

    public func test_reinstall() : async Payload {
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
            //wasm_module = "\00\61\73\6d\01\00\00\00" : Blob;
            //wasm_module = "\00\61\73\6d\01\00\00\00\01\06\01\60\01\7f\01\7f\02\14\01\07\64\66\69\6e\69\74\79\06\6d\65\6d\6f\72\79\02\01\02\03\03\02\01\00\07\07\01\03\72\75\6e\00\00\0a\10\01\0e\00\41\0a\41\2a\36\02\00\20\00\41\2a\6a\0b" : Blob;
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
