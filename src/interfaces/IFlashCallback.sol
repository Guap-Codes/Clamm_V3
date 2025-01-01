// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

interface IFlashCallback {
    function flashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external;
}
