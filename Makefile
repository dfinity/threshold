.PHONY: test

test:
	dfx --version
	yes passphrase | dfx identity new test
	dfx identity list
	dfx identity get-principal
	dfx deploy threshold \
	  --argument='(vec {principal "'$(dfx identity get-principal)'"; principal "2vxsx-fae"})'
