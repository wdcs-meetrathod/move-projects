module de_todo_objects::TodoApp{

use aptos_framework::object::{Self, ObjectGroup};
use std::timestamp;
use aptos_framework::account;
use std::signer;
use std::string::{Self, String};
use std::vector;

const E_NOT_OWNER: u64 = 1;
const E_TODO_NOT_FOUND: u64 = 2;
const E_LIST_NOT_FOUND: u64 = 3;
const E_USER_NOT_REGISTERED: u64 = 4;

struct TodoAppConfig has key {
    creator: address,
}

struct UserProfile has key {
    lists: vector<address>,
}

#[resource_group_member(group = ObjectGroup)]
struct TodoList has key {
    owner: address,
    name: String,
    description: String,
    todos: vector<address>,
    created_at: u64,
}

#[resource_group_member(group = ObjectGroup)]
struct Todo has key {
    title: String,
    description: String,
    completed: bool,
    owner: address,
    list_address: address,
}

public entry fun initialize(creator: &signer) {
    let creator_addr = signer::address_of(creator);
    let app_config = TodoAppConfig {
        creator: creator_addr,
    };

    move_to(creator, app_config);
}

public entry fun register_user(user: &signer) {
    let user_addr = signer::address_of(user);

    if (!exists<UserProfile>(user_addr)) {
        let user_profile = UserProfile {
            lists: vector::empty(),
        };

        move_to(user, user_profile);
    };
}

public entry fun create_todo_list(user: &signer, name: String, description: String) acquires UserProfile {
   let user_addr = signer::address_of(user);

   assert!(exists<UserProfile>(user_addr),E_USER_NOT_REGISTERED);


   let todo_list = TodoList{
    owner: user_addr,
    name,
    description,
    todos: vector::empty(),
    created_at: timestamp::now_seconds(), 
   };

   let constructor_ref = object::create_object(user_addr);
   let obj_signer = object::generate_signer(&constructor_ref);
   let list_addr = signer::address_of(&obj_signer);

   move_to(&obj_signer,todo_list);

   let user_profile = borrow_global_mut<UserProfile>(user_addr);
   vector::push_back(&mut user_profile.lists,list_addr);
}

public entry fun create_todo(user:&signer, list_address:address, title:String, description:String)acquires TodoList{
    let user_addr = signer::address_of(user);

    assert!(exists<UserProfile>(user_addr),E_USER_NOT_REGISTERED);

    let list = borrow_global_mut<TodoList>(list_address);
    assert!(list.owner == user_addr, E_NOT_OWNER);

    let todo_item = Todo {
        title,
        description,
        completed:false,
        owner:user_addr,
        list_address,
    };

    let constructor_ref = object::create_object(user_addr);
    let obj_signer = object::generate_signer(&constructor_ref);
    let todo_addr = signer::address_of(&obj_signer);

    move_to(&obj_signer,todo_item);

    vector::push_back(&mut list.todos, todo_addr)
}

public entry fun complete_todo(user:&signer, todo_address:address) acquires Todo {
    let user_addr = signer::address_of(user);

    assert!(exists<Todo>(todo_address),E_TODO_NOT_FOUND);

    let todo = borrow_global_mut<Todo>(todo_address);
    assert!(todo.owner == user_addr, E_NOT_OWNER);

    todo.completed = true;
}

public entry fun delete_todo(user:&signer, todo_address:address) acquires Todo, TodoList {
    let user_addr = signer::address_of(user);

    assert!(exists<Todo>(todo_address),E_TODO_NOT_FOUND);

    let todo = borrow_global_mut<Todo>(todo_address);
    assert!(todo.owner == user_addr, E_NOT_OWNER);

    let list_addr = todo.list_address;

    let list = borrow_global_mut<TodoList>(list_addr);
    assert!(list.owner == user_addr, E_NOT_OWNER);

    let (exists, index) = vector::index_of(&list.todos, &todo_address);

    if(exists){
        vector::remove(&mut list.todos, index);
    };

    // let todo_obj = object::remove<Todo>(todo_address);
    // let Todo {title:_, description:_, completed:_, owner:_, list_address:_ } = todo_obj;
}

#[view]
public fun get_user_lists(user_address:address):vector<address> acquires UserProfile{
    assert!(exists<UserProfile>(user_address),E_USER_NOT_REGISTERED);
    let user_profile = borrow_global<UserProfile>(user_address);
    user_profile.lists
}

#[view]
public fun get_list_todos(list_address:address):vector<address> acquires TodoList {
    assert!(exists<TodoList>(list_address),E_LIST_NOT_FOUND);

    let list = borrow_global<TodoList>(list_address);
    list.todos
}

#[view]
public fun get_todo_details(todo_address: address):(String, String, bool, address) acquires Todo {
    assert!(exists<Todo>(todo_address),E_TODO_NOT_FOUND);

    let todo = borrow_global<Todo>(todo_address);

    (
        todo.title,
        todo.description,
        todo.completed,
        todo.owner
    )

}

#[view]
public fun get_list_details(list_address:address):(String, String, address, u64) acquires TodoList {
    assert!(exists<TodoList>(list_address),E_LIST_NOT_FOUND);
    let list = borrow_global<TodoList>(list_address);

    (
        list.name,
        list.description,
        list.owner,
        list.created_at
    )
}

#[test]
public fun test_todo_app() acquires UserProfile, TodoList, Todo{
    let admin = account::create_account_for_test(@0x1);
    let user1 = account::create_account_for_test(@0x2);
    let user2 = account::create_account_for_test(@0x3);

    initialize(&admin);

    register_user(&user1);
    register_user(&user2);

    create_todo_list(&user1, string::utf8(b"work"),string::utf8(b"Work related tasks"));
    create_todo_list(&user1, string::utf8(b"Personal"),string::utf8(b"Personal tasks"));

    let user1_lists = get_user_lists(signer::address_of(&user1));
    assert!(vector::length(&user1_lists) == 2, 1000);

    let list_addr = *vector::borrow(&user1_lists, 0);

    create_todo(&user1, list_addr, string::utf8(b"Task 1"),string::utf8(b"Task 1"));
    create_todo(&user1, list_addr, string::utf8(b"Task 2"),string::utf8(b"Task 2"));

    let todos = get_list_todos(list_addr);
    assert!(vector::length(&todos) == 2, 1001);

    let todo_addr = *vector::borrow(&todos, 0);
    complete_todo(&user1, todo_addr);

    let (_, _, completed, _) = get_todo_details(todo_addr);
    assert!(completed == true, 1002);
}
}