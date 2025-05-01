module de_objectbox::ObjectBox {

use std::signer;
use std::vector;
use std::string::String;

use aptos_framework::object::{ObjectGroup};
use aptos_framework::object;

const E_NOT_OWNER: u64 = 1;

struct ObjectRegistry has key {
    next_box_id: u64,
    next_item_id: u64,
}

#[resource_group_member(group = ObjectGroup)]
struct Box has key {
    id: u64,
    owner: address,
    items: vector<address>
}

#[resource_group_member(group = ObjectGroup)]
struct Item has key {
    id: u64,
    label:String,
}

public entry fun initialize_registry(admin:&signer) {
    let object_registry = ObjectRegistry {
        next_box_id: 1,
        next_item_id: 1,
    };
    move_to(admin,object_registry);
}

public entry fun create_box(account:&signer){
    let addr = signer::address_of(account);
    let registry = borrow_global_mut<ObjectRegistry>(addr);
    let box_obj = Box {
        id: registry.next_box_id,
        owner:addr,
        items:vector::empty(),
    };

    registry.next_box_id  = registry.next_box_id +1;
    let constructor_ref = object::create_object_from_account(account);
    let object_signer = object::generate_signer(&constructor_ref);
    let obj_addr = signer::address_of(&object_signer);

    move_to(&object_signer,box_obj);
}

public entry fun add_item_to_box(account:&signer, box_addr:address, label:String){  
    let addr = signer::address_of(account);
    let registry = borrow_global_mut<ObjectRegistry>(addr);


    let box_obj = borrow_global_mut<Box>(box_addr);
    assert!(box_obj.owner == addr, E_NOT_OWNER);

    let item = Item {
        id: registry.next_item_id,
        label,
    };

    registry.next_item_id = registry.next_item_id + 1;

    let constructor_ref = object::create_object_from_account(account);
    let object_signer = object::generate_signer(&constructor_ref);
    let item_addr = signer::address_of(&object_signer); 

    move_to(&object_signer,item);
    vector::push_back(&mut box_obj.items, item_addr);
}

public entry fun transfer_box(sender:&signer, box_addr:address,buyer:address){
    let  box_obj = borrow_global_mut<Box>(box_addr);

    assert!(box_obj.owner == signer::address_of(sender),E_NOT_OWNER);
    box_obj.owner = buyer;

    object::transfer(sender,box_addr,buyer);
}

public entry fun delete_box(account:&signer, box_addr:address){
    let addr = signer::address_of(account);
    let box = borrow_global<Box>(box_addr);

    assert!(box.owner == addr, E_NOT_OWNER);

    let items = box.items;
    let items_len = vector::length(&items);

    let i=0;
    while(i>items_len){
        let item_addr = *vector::borrow(&items,i);
        if(object::exists_at(item_addr)){
            object::remove<Item>(item_addr);
            object::delete(account,item_addr);
        };

        i = i+1;
    };

    object::remove<Box>(box_addr);    
    object::delete(account,box_addr);
}

public fun get_box_items(box_addr:address):vector<address> acquires Box {
    let box_ref = borrow_global<Box>(box_addr);
    box_ref.items
}
}