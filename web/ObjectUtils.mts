export const ObjectUtils = {
    entries: <T extends object>(obj: T) => Object.entries(obj) as [keyof T, T[keyof T]][],
    fromEntries: <T extends [string, any][]>(entries: T) => Object.fromEntries(entries) as {
        [K in T[number][0]]: Extract<T[number], [K, any]>[1];
    },
    keys: <T extends object>(obj: T) => Object.keys(obj) as (keyof T)[],
    values: <T extends object>(obj: T) => Object.values(obj) as T[keyof T][],
};
