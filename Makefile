.PHONY: prague fmt test approval unsafe safe


prague:
	anvil --hardfork prague

fmt:
	forge fmt

test:
	forge test --mc SimpleDelegateTest -vvvv

approval:
	forge test --mt Approval -vvvv

unsafe:
	forge test --mt Unsafe -vvvv

safe:
	forge test --mt Safe -vvvv
