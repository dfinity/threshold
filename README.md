# threshold

Threshold voting and execution for the IC

## Beta quality

_Note_: This canister is not yet production quality, mostly due to a
missing test suite, however **an initial security review has been performed**.

See also the [open issues](https://github.com/dfinity/threshold/issues) for this project.

## What this canister does

- one can initially set up the canister with a collection of signers or voters (which are principals)
- one can add new proposals (by mnemonic and action, an action being the destination canister, invoked method and argument payload)
- signers can vote to accept/deny (but can't flip the vote)
- when sufficient votes for a proposal have gathered, the action gets
  executed and the proposal retired
- retired proposals can be pruned

## Setting up the signers list

When the `threshold` canister gets deployed (or reinstalled), the
initial signers list must be specified

``` shell
dfx deploy threshold --argument='(vec {principal "'$(dfx identity get-principal)'"; principal "2vxsx-fae"})'
```

_Note_: above the first principal is the `dfx` identity, so that one can vote from the command line. The second identity is the Candid GUI's, so that it can also be used.

After the installation, changes to the signers list must be done by proposals.

_CAVEAT_: if the (initial) signers list doesn't contain `threshold`'s
principal (`dfx canister id threshold`), certain self-updates will be
rejected as demonstrated in the next step...

## Example Proposal

One can send an example proposal to `threshold` by
``` shell
dfx canister call threshold submit '("haha", record {principal "rrkah-fqaaa-aaaaa-aaaaq-cai"; "accept"; vec {68; 73; 68; 76; 0; 1; 125; 1}})'
```
This will prepare the "haha" proposal (with ID `1`) which — when executed — will `accept '1'` on itself.
You'll see in the replica log that the proposal got executed by observing
```
[Canister rrkah-fqaaa-aaaaa-aaaaq-cai] ("cannot authorise", rrkah-fqaaa-aaaaa-aaaaq-cai)
```
because the canister itself is not authorised to vote.

If you have set up the signers list to contain 2 principals, then you
have to vote from the other canister too to see that error:
``` shell
dfx identity use <other>
dfx canister call threshold accept 1
```

## Self-upgrade proposal

As a proof-of-concept I included a self-upgrade code path. Before execution of a
proposal the addressee principal and the method name are compared to the management
canister's `install_code` method. If both facts match, the payload is decoded as
the official install parameters, and in case of success, the canister to be upgraded
is extracted and compared against `threshold`. If they are equal the install parameters
are used as arguments to the one-way invocation of the management canister's `install_code`
method. Since such an invocation doesn't leave a continuation context, the canister's
state machine can cleanly wind down and the upgrade succeeds.

### The concrete command

Below proposal submission command upgrades `threshold` to a `counter` canister with `get`
(query) and `inc` (update) methods.

``` shell
dfx canister call threshold submit '("self-upgrade", record {
    principal "aaaaa-aa";
    "install_code";
    blob "DIDL\03l\04\d6\fc\a7\02\01\a7\9f\c9~\01\e3\a6\83\c3\04\02\b3\c4\b1\f2\04hm{k\01\9c\e9\c6\99\06\7f\01\00\00\83\03\00asm\01\00\00\00\01\17\05\60\00\00\60\02\7f\7f\00\60\00\01\7f\60\03\7f\7f\7f\00\60\01\7f\00\02h\05\03ic0\09msg_reply\00\00\03ic0\15msg_reply_data_append\00\01\03ic0\11msg_arg_data_size\00\02\03ic0\11msg_arg_data_copy\00\03\03ic0\04trap\00\01\03\05\04\00\00\00\04\05\03\01\00\01\06\06\01~\01B\00\0b\07B\03\12canister_query get\00\05\13canister_update inc\00\06\13canister_update set\00\07\0ai\04\11\00A\07#\007\03\00A\00A\0f\10\01\10\00\0b\11\00#\00B\01|$\00A\0fA\06\10\01\10\00\0b6\00\10\02A\0fF\10\08A2A\00\10\02\10\03A2)\03\00B\08\86B\80\88\a5\a2\c4\89\c0\80\f4\00Q\10\08A9)\03\00$\00A\0fA\06\10\01\10\00\0b\0c\00 \00\0d\00A\15A\16\10\04\0b\0b3\03\00A\00\0b\07DIDL\00\01t\00A\0f\0b\06DIDL\00\00\00A\15\0b\16Invalid input argument\00\01\0a\00\00\00\00\00\00\00\01\01\01"; },)'
```
After a successful "upgrade" `threshold` will serve the `get` query:
``` shell
dfx canister call threshold --query get
(0 : int64)
```
_Note_: if you see something else, you have probably forgot to set `threshold` to be its own controller.

### Salvaging the situation

The stable memory of `threshold` is untouched by `counter`, so a subsequent `dfx deploy`
will restore it to a working state.

## Getting information out

There are only a few getters in the canister
- get the current signers' list
- get the (subset of) proposals

Both are currently defined as update methods, to completely enforce
consensus on the replies. (They used to be be queries but those would
need to apply the replicated mechanism to get the same guarantees.)
The security review has determined that this is the safer default. When
certified variables/queries are available (i.e. in place) we might
flip this default back.

All retrievals feature access control, that is only specific
principals are permitted to perform the retrieval, and the canister
traps when this is not the case.

### Getting the signers

The list of current signers can be retrieved by the current signers
only. This is a somewhat strict specification, as the knowledge of the
principal doesn't imply knowledge of the owning individual, and thus
doesn't open the door for social engineering attacks (any more than
guessing the person). So this authorisation requirement might be
removed in the future (https://github.com/dfinity/threshold/issues/12).

### Getting the proposals

There are two ways of retrieving proposals
- singular `getProposal(id)`, and
- plural `getProposals({ newest : ?Id; count : ?Nat })`.

The former, singular form is authorised based on the signers list _at
the creation time of the proposal_, thus allowing access even when a
principal has been removed from the current list.

The latter (plural) form is authorised based on the current signers
list and thus opens up retrieval of _all_ proposals for these principals.
A range of proposals can be selected by supplying a `newest` ID
(pinning the most recent proposal in the returned set) and a `count`,
specifying the maximal number of proposals to be retrieved. (If a count
is not supplied, the current default is 10 proposals, but see issue
https://github.com/dfinity/threshold/issues/10.)

## The mutual controller scheme for upgrades

If the self-upgrade facility is not desired, the user is advised to
set up `threshold` twice and configuring those such that they are
mutually the controllers of each other. This will enable each to
upgrade the other, with fall-back (or restore) abilities preserved in
cases of botched upgrades.

-------------

Welcome to your new threshold project and to the internet computer development community. By default, creating a new project adds this README and some template files to your project directory. You can edit these template files to customize your project and to include your own code to speed up the development cycle.

To get started, you might want to explore the project directory structure and the default configuration file. Working with this project in your development environment will not affect any production deployment or identity tokens.

To learn more before you start working with threshold, see the following documentation available online:

- [Quick Start](https://sdk.dfinity.org/docs/quickstart/quickstart-intro.html)
- [SDK Developer Tools](https://sdk.dfinity.org/docs/developers-guide/sdk-guide.html)
- [Motoko Programming Language Guide](https://sdk.dfinity.org/docs/language-guide/motoko.html)
- [Motoko Language Quick Reference](https://sdk.dfinity.org/docs/language-guide/language-manual.html)
- [JavaScript API Reference](https://erxue-5aaaa-aaaab-qaagq-cai.raw.ic0.app)

If you want to start working on your project right away, you might want to try the following commands:

```bash
cd threshold/
dfx help
dfx canister --help
```

## Running the project locally

If you want to test your project locally, you can use the following commands:

```bash
# Starts the replica, running in the background
dfx start --background

# Deploys your canisters to the replica and generates your candid interface
dfx deploy
```

Once the job completes, your application will be available at `http://localhost:8000?canisterId={asset_canister_id}`.

Additionally, if you are making frontend changes, you can start a development server with

```bash
npm start
```

Which will start a server at `http://localhost:8080`, proxying API requests to the replica at port 8000.

### Note on frontend environment variables

If you are hosting frontend code somewhere without using DFX, you may need to make one of the following adjustments to ensure your project does not fetch the root key in production:

- set`NODE_ENV` to `production` if you are using Webpack
- use your own preferred method to replace `process.env.NODE_ENV` in the autogenerated declarations
- Write your own `createActor` constructor
