object Person {
    .name = "Bob",
    .surname = "Aliceson",

    fn sayName() {
        print(self.name + self.surname);
    }
}

mut obj = new Person();
obj.sayName();