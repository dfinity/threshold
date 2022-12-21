.PHONY: test

test:
	dfx --version
	dfx identity list
	dfx identity use default
	dfx identity list
	dfx identity get-principal
	dfx deploy threshold \
	  --argument='(vec {principal "'$(shell dfx identity get-principal)'"; principal "2vxsx-fae"})'
	dfx canister call threshold get_signers
	dfx canister call threshold test_reinstall
	dfx canister call threshold submit '("self-upgrade", record {principal "aaaaa-aa"; "install_code"; blob "DIDL\03l\04\d6\fc\a7\02\01\a7\9f\c9~\01\e3\a6\83\c3\04\02\b3\c4\b1\f2\04hm{k\01\9c\e9\c6\99\06\7f\01\00\00\e0\01\00asm\01\00\00\00\01\0f\03\60\00\00\60\02\7f\7f\00\60\03\7f\7f\7f\00\02E\03\03ic0\09msg_reply\00\00\03ic0\15msg_reply_data_append\00\01\03ic0\11msg_arg_data_copy\00\02\03\03\02\00\00\05\03\01\00\01\078\03\06memory\02\00\15canister_update write\00\03\13canister_query read\00\04\0a:\02\22\01\01\7fA\00A\00A\01\10\02A\00(\02\00!\00 \00A\01 \00(\02\00j6\02\00\10\04\0b\15\00A\00A\00A\01\10\02A\00(\02\00A\01\10\01\10\00\0b\00\01\0a\00\00\00\00\00\00\00\01\01\01";},)'
	dfx canister call threshold accept 1
	dfx canister call threshold get_proposal 1
	dfx canister call threshold get_proposal 1
	dfx canister call threshold get_proposal 1
	dfx canister call threshold get_proposal 1
	dfx canister call threshold get_proposal 1
	dfx canister call threshold get_proposal 1
	dfx canister call threshold get_proposal 1
	dfx canister call threshold get_proposal 1
	sleep 10
	dfx canister call threshold --query get
