// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ESynth} from "euler-vault-kit/Synths/ESynth.sol";

/// @title nUSD
/// @custom:security-contact security@euler.xyz
/// @author Valentin Mihov (valentin.mihpv@gmail.com)
/// @notice A syntetix USD token which is backed by over collateralized assets.
contract nUSD is ESynth {
    constructor(address evc_, string memory name_, string memory symbol_)
        ESynth(evc_, name_, symbol_)
    {
    }
}