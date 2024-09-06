

export function declareStyle<const T extends Record<string, unknown>>(
  style: T & Record<keyof T, Partial<CSSStyleDeclaration>
    | Record<`&:${string}`, Partial<CSSStyleDeclaration>>>
) {
  // Build lookup of class names to class name as a string.
  const classList: (keyof T)[] = Object.keys(style).reduce((acc, key) => {
    const keys = key.split('.');
    return [...acc, ...keys];
  }, [] as any);
  const classes: { [key in keyof T]: key } = classList.reduce((acc, key) => {
    acc[key as string] = key;
    return acc;
  }, {} as any);
  const classAndSubclassList: [string, any][] = classList.reduce((unwrappedDefns, className) => {
    const classContents = style[className];
    const subClasses = Object.keys(classContents).filter((key) => key.startsWith('&')).map((subclassKey) => {
      const subKey = `${className as any}${subclassKey.split('&')[1]}`;
      classContents[subKey as keyof typeof classContents] = undefined as any;
      return [subKey, classContents[subclassKey as keyof typeof classContents]] as const;
    });
    return [...unwrappedDefns, [className, classContents] as const, ...subClasses];
  }, [] as any);
  const encodedStyle = classAndSubclassList.map((entry) => {
    const [objectKey, contents] = entry;
    return `.${objectKey as string} {${Object.keys(contents).map((key) => {
      const dashedKey = key.replace(/[A-Z]/g, match => `-${match.toLowerCase()}`);
      return `${dashedKey}: ${contents[key as any]};`
    }).join('')}}`
  }).join('');
  return { classes, encodedStyle };
}
