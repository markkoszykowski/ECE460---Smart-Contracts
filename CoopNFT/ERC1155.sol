// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC1155.sol";
import "./IERC1155Receiver.sol";
import "./IERC1155MetadataURI.sol";
import "./Address.sol";
import "./Context.sol";
import "./ERC165.sol";

/**
 *
 * @dev Implementation of the basic standard multi-token.
 * See https://eips.ethereum.org/EIPS/eip-1155
 * Originally based on code by Enjin: https://github.com/enjin/erc-1155
 *
 * _Available since v3.1._
 */
contract ERC1155 is Context, ERC165, IERC1155, IERC1155MetadataURI {
    using Address for address;
    
    // Mapping from token ID to account balances
    mapping (uint256 => mapping(address => uint256)) private _balances;

    // Mapping from account to operator approvals
    mapping (address => mapping(address => bool)) private _operatorApprovals;

    // Used as the URI for all token types
    string private _uri;
    
    // NEW
    // Mapping from token ID to URI
    mapping (uint256 => string) private _tokenPublicUri;
    mapping (uint256 => string) private _tokenPrivateUri;
    
    // NEW
    // Mapping from token ID to account
    mapping (uint256 => address[]) private _creators;
    
    // NEW
    // Mapping from account to piece locks
    // True - locked
    // False - unlocked
    mapping (uint256 => bool) _locks;
    
    // NEW
    // System admin
    address private _admin;

    /**
     * @dev See {_setURI}.
     * @dev See {_setAdmin}.
     */
    constructor (string memory uri_, address admin_) {
        _setURI(uri_);
        _setAdmin(admin_);
    }
    
    
    // NEW
    // Possibly switch to check for a certain account for security
    function getAdmin() public view returns (address) {
        return _admin;
    }
    
    // NEW
    // Simple function to change the system admin
    function changeAdmin(address newAdmin_) public {
        require(_msgSender() == _admin, "ERC1155: not the current admin");
        _setAdmin(newAdmin_);
    }
    
    // NEW
    // Simple function to unlock data for a creator based on token ID
    // Requirements:
    //
    //  - '_msgSender' is the '_admin'
    //
    function unlock(uint256 id_, address[] memory creators_) public {
        require(_msgSender() == _admin, "ERC1155: not the current admin");
        _locks[id_] = false;
        _creators[id_] = creators_;
        emit Unlocked(creators_, id_, _tokenPublicUri[id_], _tokenPrivateUri[id_]);
    }
    
    // NEW
    // simple function to check if data is unlocked
    function isLocked(uint256 id_) public view returns (bool) {
        return _safeLockCheck(id_);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
     
     
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155).interfaceId
            || interfaceId == type(IERC1155MetadataURI).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC1155MetadataURI-uri}.
     *
     * This implementation returns the same URI for *all* token types.
     *
     */
    function uri(uint256) public view virtual override returns (string memory) {
        return _uri;
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        require(account != address(0), "ERC1155: balance query for the zero address");
        return _balances[id][account];
    }

    /**
     * @dev See {IERC1155-balanceOfBatch}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(
        address[] memory accounts,
        uint256[] memory ids
    )
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        require(accounts.length == ids.length, "ERC1155: accounts and ids length mismatch");

        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }

        return batchBalances;
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(_msgSender() != operator, "ERC1155: setting approval status for self");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address account, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[account][operator];
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    )
        public
        virtual
        override
    {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );
        
        _safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        public
        virtual
        override
    {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: transfer caller is not owner nor approved"
        );
        
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }
    
    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSinglePublic} event if piece is locked, otherwise emits a {TransferSinglePrivate} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    )
        internal
        virtual
    {
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();

        uint256 fromBalance = _balances[id][from];
        require(fromBalance >= amount, "ERC1155: insufficient balance for transfer");
        _balances[id][from] = fromBalance - amount;
        _balances[id][to] += amount;

        if (isLocked(id)) {
            emit TransferSinglePublic(operator, from, to, id, amount, _tokenPublicUri[id]);
        } else {
            emit TransferSinglePrivate(operator, from, to, id, amount, _creators[id], _tokenPublicUri[id], _tokenPrivateUri[id]);
        }

        _doSafeTransferAcceptanceCheck(operator, from, to, id, amount, data);
    }
    
    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_safeTransferFrom}.
     *
     * Emits {TransferSinglePublic} events if pieces are locked, otherwise emits {TransferSinglePrivate} events.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        internal
        virtual
    {
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            uint256 fromBalance = _balances[id][from];
            require(fromBalance >= amount, "ERC1155: insufficient balance for transfer");
            _balances[id][from] = fromBalance - amount;
            _balances[id][to] += amount;
            
            if (isLocked(id)) {
                emit TransferSinglePublic(operator, from, to, id, amount, _tokenPublicUri[id]);
            } else {
                emit TransferSinglePrivate(operator, from, to, id, amount, _creators[id], _tokenPublicUri[id], _tokenPrivateUri[id]);
            }
        }

        _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, amounts, data);
    }

    /**
     * @dev Sets a new URI for all token types.
     *
     * See {uri}.
     *
     * Because these URIs cannot be meaningfully represented by the {URI} event,
     * this function emits no events.
     */
    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }
    
    // NEW
    // simple functin to set and admin
    function _setAdmin(address newadmin) internal {
        _admin = newadmin;
    }
    
    // NEW
    // simple function that returns whether a piece's data is locked
    function _safeLockCheck(uint256 id) internal view returns (bool) {
        return _locks[id];
    }

    /**
     * @dev Creates `amount` tokens of token type `id`, and assigns them to `account`.
     *
     * Emits a {TransferSinglePublic} event.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - If `account` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _mint(address account, uint256 id, uint256 amount, string memory publicUri, string memory privateUri, bytes memory data) public virtual {
        require(account != address(0), "ERC1155: mint to the zero address");

        address operator = _msgSender();
    
        // assume peices are originally minted to the centralized Cooper wallet
        _locks[id] = true;
        _balances[id][account] += amount;
        _tokenPublicUri[id] = publicUri;
        _tokenPrivateUri[id] = privateUri;
        emit TransferSinglePublic(operator, address(0), account, id, amount, publicUri);

        _doSafeTransferAcceptanceCheck(operator, address(0), account, id, amount, data);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_mint}.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function _mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, string[] memory publicUris, string[] memory privateUris, bytes memory data) public virtual {
        require(to != address(0), "ERC1155: mint to the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
        require(ids.length == publicUris.length, "ERC1155: ids and public uris length mismatch");
        require(privateUris.length == publicUris.length, "ERC1155: private uris and public uris length mismatch");

        address operator = _msgSender();

        for (uint i = 0; i < ids.length; i++) {
            // assume peices are originally minted to the centralized Cooper wallet
            _locks[ids[i]] = true;
            _balances[ids[i]][to] += amounts[i];
            _tokenPublicUri[ids[i]] = publicUris[i];
            _tokenPrivateUri[ids[i]] = privateUris[i];
        }

        emit TransferBatchPublic(operator, address(0), to, ids, amounts, publicUris);

        _doSafeBatchTransferAcceptanceCheck(operator, address(0), to, ids, amounts, data);
    }

    /**
     * @dev Destroys `amount` tokens of token type `id` from `account`
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens of token type `id`.
     */
    function _burn(address account, uint256 id, uint256 amount) public virtual {
        require(account != address(0), "ERC1155: burn from the zero address");

        address operator = _msgSender();

        uint256 accountBalance = _balances[id][account];
        require(accountBalance >= amount, "ERC1155: burn amount exceeds balance");
        _balances[id][account] = accountBalance - amount;

        emit TransferSinglePublic(operator, account, address(0), id, amount, "");
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_burn}.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     */
    function _burnBatch(address account, uint256[] memory ids, uint256[] memory amounts) public virtual {
        require(account != address(0), "ERC1155: burn from the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        for (uint i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            uint256 accountBalance = _balances[id][account];
            require(accountBalance >= amount, "ERC1155: burn amount exceeds balance");
            _balances[id][account] = accountBalance - amount;
        }

        emit TransferBatchPublic(operator, account, address(0), ids, amounts, new string[](ids.length));
    }

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    )
        private
    {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                if (response != IERC1155Receiver(to).onERC1155Received.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        private
    {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (bytes4 response) {
                if (response != IERC1155Receiver(to).onERC1155BatchReceived.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

}
