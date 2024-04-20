// import { Scripting, AllowedKeys } from "./Util.Scripting";
// import { Vec2, Vec3, Vec4 } from "./Util.VecMath";

export function getKeys<T extends object>(obj: T) {
    return Object.keys(obj) as (keyof T)[];
}

export type Vec2 = readonly [number, number];
export type Vec3 = readonly [number, number, number];
export type Vec4 = readonly [number, number, number, number];
export type Quat = readonly [number, number, number, number];
export type Mat2 = [number, number, number, number];
export type Mat3x2 = [number, number, number, number, number, number];
export type Mat3 = [number, number, number, number, number, number, number, number, number];
export type Mat4 = [
	number, number, number, number,
	number, number, number, number,
	number, number, number, number,
	number, number, number, number
];
export type FilterFlags<Base, Condition> = {
    [Key in keyof Base]: Base[Key] extends Condition ? Key : never
};
export type AllowedKeys<Base, Condition> =
    FilterFlags<Base, Condition>[keyof Base];



export type GLSLUnit = "float" | "vec2" | "vec3" | "vec4";
export type GLSLUniformUnit = "float" | "vec2" | "vec3" | "vec4" | "sampler2D" | "mat4";
export type Varying = {
	readonly type: "varying",
	readonly unit: GLSLUnit,
};
export type Attribute = {
	readonly type: "attribute",
	readonly unit: GLSLUnit,
	readonly instanced?: true,
};
export type Element = {
	readonly type: "element",
};
export type Uniform = {
	readonly type: "uniform",
	readonly unit: GLSLUniformUnit,
	readonly count: 1 | UniformSizes,
};
export const unitToStride = {
	float: 1,
	vec2: 2,
	vec3: 3,
	vec4: 4,
    mat4: 16,
} as const;
export type Texture = {
	texture: WebGLTexture,
	width: number,
	height: number,
}
export type UniformSizes =
	2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
	17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 | 32;
export type SizedBuffer = {
	type: "attribute",
	buffer: WebGLBuffer,
	length: number,
};
export type ElementBuffer = {
	type: "element",
	buffer: WebGLBuffer,
	length: number,
};
export type Binds<T> =
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "float", count: 1 }>]: number }
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "vec2", count: 1 }>]: Vec2 }
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "vec3", count: 1 }>]: Vec3 }
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "vec4", count: 1 }>]: Vec4 }
    & { readonly [key in AllowedKeys<T, { type: "uniform", unit: "mat4", count: 1 }>]: Mat4 }
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "sampler2D", count: 1 }>]: Texture }
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "float", count: UniformSizes }>]: readonly number[] }
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "vec2", count: UniformSizes }>]: readonly Vec2[] }
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "vec3", count: UniformSizes }>]: readonly Vec3[] }
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "vec4", count: UniformSizes }>]: readonly Vec4[] }
    & { readonly [key in AllowedKeys<T, { type: "uniform", unit: "mat4", count: UniformSizes }>]: readonly Mat4[] }
	& { readonly [key in AllowedKeys<T, { type: "uniform", unit: "sampler2D", count: UniformSizes }>]: readonly Texture[] }
	& { readonly [key in AllowedKeys<T, Attribute>]: SizedBuffer }
	& { readonly [key in AllowedKeys<T, Element>]: ElementBuffer }

export type ShaderGlobals = {
	readonly [key: string]:
	| Varying
	| Attribute
	| Uniform
	| Element
};

export namespace ShaderBuilder {

	export function varyingText(key: string, element: Varying) {
		return `${element.type} highp ${element.unit} ${key};`;
	}

	export function attributeText(key: string, element: Attribute) {
		return `${element.type} ${element.unit} ${key}; `
	}

	export function uniformText(key: string, element: Uniform) {
		return `${element.type} ${
			element.unit == "sampler2D" ? `` : `highp`} ${element.unit} ${key}${
			element.count > 1 ? `[${element.count}]` : ``};`
	}

	export function toVertText(props: ShaderGlobals) {
		return getKeys(props).reduce((text, key) => {
			const element = props[key];
			return `${text}\n ${
				element.type == "varying" ?
					varyingText(key as string, element) :
					element.type == "attribute" ?
						attributeText(key as string, element) :
						element.type == "uniform" ?
							uniformText(key as string, element) :
							""
				}`;
		}, "");
	}

	export function toFragText(props: ShaderGlobals) {
		return getKeys(props).reduce((text, key) => {
			const element = props[key];
			return `${text}${
				element.type == "varying" ?
					varyingText(key as string, element) :
					element.type == "uniform" ?
						uniformText(key as string, element) :
						""
				}\n`;
		}, "");

	}
	export type Environment<T extends ShaderGlobals> = {
		readonly globals: T,
		readonly vertSource: string,
		readonly fragSource: string,
		readonly mode: "TRIANGLES" | "TRIANGLE_STRIP",
	};

	export type Material<T extends ShaderGlobals> = {
		readonly program: WebGLProgram,
	} & Environment<T>;

	export function generateMaterial<T extends ShaderGlobals>(
		gl: WebGL2RenderingContext,
		environment: Environment<T>,
	) {
		// ✨🎨 Create fragment shader object
		const program = gl.createProgram();
		if (program == null) {
			throw new Error("Vertex/Fragment shader not properly initialized");
		}
		const vertSource = `
			${toVertText(environment.globals)}
			${environment.vertSource}
		`;
		const fragSource = `
			${toFragText(environment.globals)}
			${environment.fragSource}
		`;
		[vertSource, fragSource].forEach((source, index) => {
			const shader = gl.createShader(index == 0 ? gl.VERTEX_SHADER : gl.FRAGMENT_SHADER);
			if (shader == null) {
				throw new Error("Vertex/Fragment shader not properly initialized");
			}
			gl.shaderSource(shader, source);
			gl.compileShader(shader);
			gl.attachShader(program, shader);
			if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
                console.log(source);
				const splitInfo = gl.getShaderInfoLog(shader)?.split("ERROR:");
				if (splitInfo != null) {
					const errors = splitInfo.slice(1, splitInfo?.length);
					for (let error of errors) {
						const location = error.split(":")[1];
						console.log(source.split("\n")[parseInt(location) - 1])
						console.error(error);
					}
				}
			}
		});

		gl.linkProgram(program);

		return {
			...environment,
			program,
			fragSource,
			vertSource,
		} as const;
	}

    export function loadImageData(gl: WebGL2RenderingContext, data: Uint8Array, width: number, height: number) {
        const texture = gl.createTexture();
        if (texture == null) {
            throw new Error("Texture is null, this is not expected!");
        }
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.generateMipmap(gl.TEXTURE_2D);
        return {
            texture,
            width,
            height,
        };
    }

	export async function loadTexture(gl: WebGL2RenderingContext, url: string) {
		return await new Promise<Texture>((resolve) => {
			const texture = gl.createTexture();
			if (texture == null) {
				throw new Error("Texture is null, this is not expected!");
			}
			gl.bindTexture(gl.TEXTURE_2D, texture);

			const textureSettings = {
				level: 0,
				internalFormat: gl.RGBA,
				srcFormat: gl.RGBA,
				srcType: gl.UNSIGNED_BYTE,
			};

			const image = new Image();
			image.onload = () => {
				gl.bindTexture(gl.TEXTURE_2D, texture);
				gl.texImage2D(gl.TEXTURE_2D, textureSettings.level, textureSettings.internalFormat,
					textureSettings.srcFormat, textureSettings.srcType, image);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
				gl.generateMipmap(gl.TEXTURE_2D);
				resolve({
					texture,
					width: image.width,
					height: image.height,
				});
			};
			image.src = url;
		});
	}

	export function createElementBuffer(gl: WebGL2RenderingContext, data: Uint16Array | Uint32Array): ElementBuffer {
		const buffer = gl.createBuffer();
		if (buffer == null) {
			throw new Error("Buffer is null, this is not expected!");
		}
		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffer);
		gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, data, gl.STATIC_DRAW);
		return { type: "element", buffer, length: data.length };
	}

	export function createBuffer(gl: WebGL2RenderingContext, data: Float32Array): SizedBuffer {
		const buffer = gl.createBuffer();
		if (buffer == null) {
			throw new Error("Buffer is null, this is not expected!");
		}
		gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
		gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
		return { type: "attribute", buffer, length: data.length };
	}

	export function renderMaterial<T extends ShaderGlobals>(
		gl: WebGL2RenderingContext,
		material: Material<T>,
		binds: Binds<T>,
	) {
		gl.useProgram(material.program);

		{ // 🦗 Setting uniform variables including textures
			Object.entries(material.globals)
				.filter((entry): entry is [string, Uniform] =>
					entry[1].type == "uniform")
				.reduce((textureIndex, entry) => {
					const [key, global] = entry;
					const uniformLocation = gl.getUniformLocation(material.program, key as string);

					const data = (binds as any)[key];
					switch (global.unit) {
						case "sampler2D":
							const textures = global.count > 1 ? data as Texture[] : [data as Texture];
							const indices = textures.map((data, subIndex) => {
								const activeTextureIndex = textureIndex + subIndex;
								gl.activeTexture(gl.TEXTURE0 + activeTextureIndex);
								gl.bindTexture(gl.TEXTURE_2D, data.texture);
								return activeTextureIndex;
							})
							gl.uniform1iv(uniformLocation, indices);
							return textureIndex + indices.length;
						case "float":
							gl.uniform1fv(uniformLocation, global.count > 1 ? data as number[] : [data as number]);
							break;
						case "vec2":
							gl.uniform2fv(uniformLocation, global.count > 1 ? (data as Vec2[]).flat() : [...data as Vec2]);
							break;
						case "vec3":
							gl.uniform3fv(uniformLocation, global.count > 1 ? (data as Vec3[]).flat() : [...data as Vec3]);
							break;
						case "vec4":
							gl.uniform4fv(uniformLocation, global.count > 1 ? (data as Vec4[]).flat() : [...data as Vec4]);
							break;
                        case "mat4":
                            gl.uniformMatrix4fv(uniformLocation, false, global.count > 1 ? (data as Mat4[]).flat() : [...data as Mat4]);
                            break;
					}
					return textureIndex;
				}, 0);
		}

		{ // 👇 Set the points of the triangle to a buffer, assign to shader attribute
			Object.entries(material.globals)
				.filter((entry): entry is [typeof entry[0], Attribute] =>
					entry[1].type == "attribute")
				.forEach(entry => {
					const [key, global] = entry;
					const data = (binds as any)[key] as SizedBuffer;
					gl.bindBuffer(gl.ARRAY_BUFFER, data.buffer);
					const attributeLocation = gl.getAttribLocation(material.program, key as string);
                    if (attributeLocation == -1) {
                        console.error(`Attribute ${key} not found in shader`);
                        return;
                    }
					const dataType = global.unit;
					gl.vertexAttribPointer(attributeLocation, unitToStride[dataType], gl.FLOAT, false, 0, 0);
					gl.enableVertexAttribArray(attributeLocation);
					if (global.instanced) {
						gl.vertexAttribDivisor(attributeLocation, 1);
					}
				});
		}

		// 🖌 Draw the arrays/elements using size determined from aggregating buffers
		{
			const bufferCounts = Object.entries(material.globals)
				.filter((entry): entry is [typeof entry[0], Attribute] =>
					entry[1].type == "attribute")
				.reduce((bufferCounts, entry) => {
					const [key, global] = entry;
					const data = (binds as any)[key] as SizedBuffer;
					const stride = unitToStride[global.unit];
					return global.instanced ?
						{
							...bufferCounts,
							instance: Math.max(bufferCounts.instance, data.length / stride),
						} :
						{
							...bufferCounts,
							element: Math.max(bufferCounts.element, data.length / stride),
						};
				}, { element: 0, instance: 1 });
			const elementEntry = Object.entries(material.globals)
				.find((entry): entry is [typeof entry[0], Element] =>
					entry[1].type == "element");
			if (elementEntry != null) {
				const [elementKey] = elementEntry;
				const data = (binds as any)[elementKey] as SizedBuffer;
				gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, data.buffer);

				gl.drawElementsInstanced(gl[material.mode], data.length, gl.UNSIGNED_SHORT, 0, bufferCounts.instance);
			} else {
				gl.drawArraysInstanced(gl[material.mode], 0, bufferCounts.element, bufferCounts.instance);
			}
		}
	}

	export function cleanupResources<T extends Record<string, Texture | SizedBuffer | ElementBuffer>>(gl: WebGL2RenderingContext, binds: T) {
		Object.values(binds).forEach((bind) => {
			if ("type" in bind && (bind.type == "attribute" || bind.type == "element")) {
				gl.deleteBuffer(bind.buffer);
			} else {
				gl.deleteTexture(bind.texture);
			}
		});
	}
}