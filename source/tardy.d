module tardy;


/**
   A wrapper that acts like a subclass of Interface, dispatching
   at runtime to different model instances.
 */
struct Polymorphic(Interface) if(is(Interface == interface)){

    private void* _model;
    private immutable VirtualTable!Interface _vtable;

    this(void* model, immutable VirtualTable!Interface vtable) {
        _model = model;
        _vtable = vtable;
    }

    this(Model)(Model model) {
        this(constructModel(model), vtable!(Interface, Model));
    }

    static construct(alias module_, Model)(Model model) {
        return Polymorphic!Interface(constructModel(model), vtable!(Interface, Model, module_));
    }

    /**
       This factory function makes it possible to pass in modules
       to look for UFCS functions for the model
     */
    template create(Modules...) {
        static create(Model)(Model model) {
            return Polymorphic!Interface(constructModel(model),
                                         vtable!(Interface, Model, Modules));
        }
    }

    private static void* constructModel(Model)(Model model) {
        auto newModel = new Model;
        *newModel = model;
        return newModel;
    }

    auto opDispatch(string identifier, A...)(A args) inout {
        mixin(`return _vtable.`, identifier, `(_model, args);`);
    }
}


/**
   A virtual table for Interface.

   Has one function pointer slot for every function declared
   in the interface type.
 */
struct VirtualTable(Interface) if(is(Interface == interface)) {
    // FIXME:
    // * argument defaults e.g. int i = 42
    // * `this` modifiers (const, scope, ...)
    // * @safe pure
    // * overloads
    import std.traits: ReturnType, Parameters;

    private enum member(string name) = __traits(getMember, Interface, name);

    // Here we declare one function pointer per declaration in Interface.
    // Each function pointer has the same return type and one extra parameter
    // in the first position which is the model or context.
    static foreach(name; __traits(allMembers, Interface)) {
        // FIXME: decide when to use void* vs const void*
        mixin(`ReturnType!(Interface.`, name, `) function(const void*, Parameters!(Interface.`, name, `)) `, name, `;`);
    }
}


/**
   Creates a virtual table for the given Instance that implements
   the given Interface.

   This function assigns every slot in VirtualTable!Interface with
   a function pointer that delegates to the Instance type.
 */
auto vtable(Interface, Instance, Modules...)() {

    import std.conv: text;
    import std.string: join;
    import std.traits: Parameters, fullyQualifiedName;
    import std.algorithm: map;
    import std.range: iota;

    VirtualTable!Interface ret;

    // 0 -> arg0, 1 -> arg1, ...
    static string argName(size_t i) { return `arg` ~ i.text; }
    // func -> arg0, arg1, ...
    static string argsList(string name)() {
        alias method = mixin(`Interface.`, name);
        return Parameters!method
            .length
            .iota
            .map!argName
            .join(`, `);
    }

    template moduleName(alias module_) {
        static if(is(typeof(module_) == string))
            enum moduleName = module_;
        else
            enum moduleName = fullyQualifiedName!(module_);
    }

    template moduleSymbol(alias module_) {
        static if(is(typeof(module_) == string)) {
            mixin(`import the_module = `, module_, `;`);
            alias moduleSymbol = the_module;
        }
        else
            alias moduleSymbol = module_;
    }

    enum importMixin(alias module_, string name) = `import ` ~ moduleName!module_ ~ `:` ~ name ~ `;`;

    static foreach(name; __traits(allMembers, Interface)) {{
        // import any modules where we have to look for UFCS implementations
        static foreach(module_; Modules) {
            static if(__traits(hasMember, moduleSymbol!module_, name))
                mixin(importMixin!(module_, name));
        }

        // e.g. ret.foo = (self, arg0, arg1) => (cast (Instance*) self).foo(arg0, arg1);
        mixin(`ret.`, name, ` = (self, `, argsList!name, `) => (cast (Instance*) self).`, name, `(`, argsList!name, `);`);
    }}

    return ret;
}