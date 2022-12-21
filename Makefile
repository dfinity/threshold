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
