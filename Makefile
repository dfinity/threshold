.PHONY: test self-upgrade

test:
	dfx --version
	dfx identity list
	dfx identity use default
	dfx identity list
	dfx identity get-principal
	dfx deploy threshold --mode reinstall --yes --with-cycles 8000000000000 \
	  --argument='(vec {principal "'$$(dfx identity get-principal)'"; principal "2vxsx-fae"})'
	dfx canister call threshold getSigners
	echo id: $$(dfx canister id threshold)
	dfx canister call threshold submit '("purge", record { principal "'$$(dfx canister id threshold)'"; "prune"; blob "DIDL\00\00" })'
	dfx canister call threshold getProposal 1
	dfx canister call threshold accept 1
	dfx identity use anonymous
	dfx canister call threshold accept 1
	sleep 1
	dfx canister call threshold getProposal 1 | tee result
	echo '(null)' | diff - result
	dfx identity use default

self-upgrade:
	dfx --version
	- dfx stop
	dfx start --clean --background
	dfx identity use default
	dfx identity list
	dfx canister create threshold --specified-id rrkah-fqaaa-aaaaa-aaaaq-cai
	dfx deploy threshold --with-cycles 8000000000000 \
	  --argument='(vec {principal "'$$(dfx identity get-principal)'"; principal "2vxsx-fae"})'
	dfx canister call threshold getSigners
	dfx canister update-settings threshold --add-controller $$(dfx canister id threshold)
	dfx canister call threshold submit '("self-upgrade", record { principal "aaaaa-aa"; "install_code"; blob "DIDL\03l\04\d6\fc\a7\02\01\a7\9f\c9~\01\e3\a6\83\c3\04\02\b3\c4\b1\f2\04hm{k\01\9c\e9\c6\99\06\7f\01\00\00\83\03\00asm\01\00\00\00\01\17\05\60\00\00\60\02\7f\7f\00\60\00\01\7f\60\03\7f\7f\7f\00\60\01\7f\00\02h\05\03ic0\09msg_reply\00\00\03ic0\15msg_reply_data_append\00\01\03ic0\11msg_arg_data_size\00\02\03ic0\11msg_arg_data_copy\00\03\03ic0\04trap\00\01\03\05\04\00\00\00\04\05\03\01\00\01\06\06\01~\01B\00\0b\07B\03\12canister_query get\00\05\13canister_update inc\00\06\13canister_update set\00\07\0ai\04\11\00A\07#\007\03\00A\00A\0f\10\01\10\00\0b\11\00#\00B\01|\24\00A\0fA\06\10\01\10\00\0b6\00\10\02A\0fF\10\08A2A\00\10\02\10\03A2)\03\00B\08\86B\80\88\a5\a2\c4\89\c0\80\f4\00Q\10\08A9)\03\00\24\00A\0fA\06\10\01\10\00\0b\0c\00 \00\0d\00A\15A\16\10\04\0b\0b3\03\00A\00\0b\07DIDL\00\01t\00A\0f\0b\06DIDL\00\00\00A\15\0b\16Invalid input argument\00\01\0a\00\00\00\00\00\00\00\01\01\01";},)'
	dfx canister call threshold getProposal 1
	dfx canister call threshold accept 1
	dfx canister id threshold
	echo id: $$(dfx canister id threshold)
	echo principal: $$(dfx identity get-principal)
	dfx identity use anonymous
	dfx canister call threshold accept 1
	dfx identity use default
	sleep 2
	dfx canister call threshold --query get
	- dfx canister call threshold getProposal 1
