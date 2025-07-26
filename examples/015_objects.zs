object MyObj {
    .name = "Hello World!"

    fn log() {
        print(self.name);
    }
}

immut obj = new MyObj();
obj.log();