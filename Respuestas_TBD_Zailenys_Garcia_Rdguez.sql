-- ============================================================================
-- RESPUESTAS DE TALLER DE BASES DE DATOS - Zailenys García Rodríguez
-- PostgreSQL 18
-- Esquema: punto_de_venta
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS punto_de_venta;
SET search_path TO punto_de_venta, public;

-- ============================================================================
-- EJERCICIO 1. CREACIÓN DE TIPOS COMPUESTOS
-- ============================================================================

-- Tipo compuesto reutilizable para las direcciones de clientes,
-- puntos de venta y vendedores.
CREATE TYPE tdireccion AS (
    calle       text,
    numero      text,
    entrecalle1 text,
    entrecalle2 text,
    reparto     text
);

-- Tipo compuesto que representa cada producto dentro del arreglo detalle
-- de una venta.
CREATE TYPE tdetalle AS (
    idproducto   integer,
    idfabricante integer,
    cantidad     numeric(10,2),
    descuento    numeric(10,2),
    precioventa  numeric(10,2)
);

-- Tipo compuesto correspondiente a la tabla ciudad.
CREATE TYPE tciudad AS (
    idciudad integer,
    nombre   text,
    region   text
);

-- Tipo compuesto correspondiente a la tabla cliente.
CREATE TYPE tcliente AS (
    idcliente integer,
    nombre    text,
    apellidos text,
    direccion tdireccion
);

-- Tipo compuesto correspondiente a la tabla fabricante.
CREATE TYPE tfabricante AS (
    idfabricante integer,
    nombre       text
);

-- Tipo compuesto correspondiente a la tabla punto de venta.
CREATE TYPE tpdv AS (
    idpdv           integer,
    planventas_real numeric(12,2),
    nombre          text,
    direccion       tdireccion,
    idciudad        integer
);

-- Tipo compuesto correspondiente a la tabla producto.
CREATE TYPE tproducto AS (
    idprod       integer,
    idfabricante integer,
    nombre       text,
    um           text,
    preciobasico numeric(10,2)
);

-- Tipo compuesto correspondiente a la tabla vendedor.
CREATE TYPE tvendedor AS (
    idvendedor     integer,
    planventasreal numeric(12,2),
    nombre         text,
    apellidos      text,
    direccion      tdireccion,
    idpdv          integer,
    responsable    integer
);

-- Tipo compuesto correspondiente a la tabla venta.
CREATE TYPE tventa AS (
    nrofactura integer,
    idvendedor integer,
    idcliente  integer,
    divisa     boolean,
    fechahora  timestamp,
    detalle    tdetalle[]
);

-- ============================================================================
-- EJERCICIO 2. CREACIÓN DE TABLAS Y RESTRICCIONES REFERENCIALES
-- ============================================================================

CREATE TABLE ciudad OF tciudad (
    idciudad WITH OPTIONS NOT NULL,
    nombre WITH OPTIONS NOT NULL,
    region WITH OPTIONS NOT NULL,
    CONSTRAINT pk_ciudad PRIMARY KEY (idciudad),
    CONSTRAINT ck_ciudad_region
        CHECK (region IN ('Occidente', 'Centro', 'Oriente'))
);

CREATE TABLE cliente OF tcliente (
    idcliente WITH OPTIONS NOT NULL,
    nombre WITH OPTIONS NOT NULL,
    apellidos WITH OPTIONS NOT NULL,
    CONSTRAINT pk_cliente PRIMARY KEY (idcliente)
);

CREATE TABLE fabricante OF tfabricante (
    idfabricante WITH OPTIONS NOT NULL,
    nombre WITH OPTIONS NOT NULL,
    CONSTRAINT pk_fabricante PRIMARY KEY (idfabricante)
);

CREATE TABLE pdv OF tpdv (
    idpdv WITH OPTIONS NOT NULL,
    planventas_real WITH OPTIONS NOT NULL,
    nombre WITH OPTIONS NOT NULL,
    idciudad WITH OPTIONS NOT NULL,
    CONSTRAINT pk_pdv PRIMARY KEY (idpdv),
    CONSTRAINT fk_pdv_ciudad
        FOREIGN KEY (idciudad) REFERENCES ciudad(idciudad)
);

CREATE TABLE producto OF tproducto (
    idprod WITH OPTIONS NOT NULL,
    idfabricante WITH OPTIONS NOT NULL,
    nombre WITH OPTIONS NOT NULL,
    um WITH OPTIONS NOT NULL,
    preciobasico WITH OPTIONS NOT NULL,
    CONSTRAINT pk_producto PRIMARY KEY (idprod, idfabricante),
    CONSTRAINT ck_producto_preciobasico CHECK (preciobasico > 0),
    CONSTRAINT fk_producto_fabricante
        FOREIGN KEY (idfabricante) REFERENCES fabricante(idfabricante)
);

-- vendedor se crea como tabla ordinaria con los atributos del tipo tvendedor.
-- Esta decisión permite utilizarla como tabla padre de gerente mediante
-- la herencia solicitada en el ejercicio 7.
CREATE TABLE vendedor (
    idvendedor     integer PRIMARY KEY,
    planventasreal numeric(12,2) NOT NULL,
    nombre         text NOT NULL,
    apellidos      text NOT NULL,
    direccion      tdireccion,
    idpdv          integer NOT NULL,
    responsable    integer,
    CONSTRAINT fk_vendedor_pdv
        FOREIGN KEY (idpdv) REFERENCES pdv(idpdv),
    CONSTRAINT fk_vendedor_responsable
        FOREIGN KEY (responsable) REFERENCES vendedor(idvendedor)
);

CREATE TABLE venta OF tventa (
    nrofactura WITH OPTIONS NOT NULL,
    idvendedor WITH OPTIONS NOT NULL,
    idcliente WITH OPTIONS NOT NULL,
    divisa WITH OPTIONS NOT NULL DEFAULT false,
    fechahora WITH OPTIONS NOT NULL,
    detalle WITH OPTIONS NOT NULL DEFAULT '{}',
    CONSTRAINT pk_venta PRIMARY KEY (nrofactura),
    CONSTRAINT fk_venta_vendedor
        FOREIGN KEY (idvendedor) REFERENCES vendedor(idvendedor),
    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (idcliente) REFERENCES cliente(idcliente)
);

-- ============================================================================
-- EJERCICIO 3. PUNTOS DE VENTA UBICADOS EN UNA CIUDAD
-- La función recibe el nombre de una ciudad y devuelve los nombres de los
-- puntos de venta que se encuentran en ella.
-- ============================================================================

CREATE OR REPLACE FUNCTION pdv_por_ciudad(p_nombre_ciudad text)
RETURNS TABLE (
    nom_pdv text
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- Se relacionan las tablas pdv y ciudad mediante el identificador
    -- de la ciudad para localizar los puntos de venta correspondientes.
    -- ILIKE permite comparar el nombre sin distinguir mayúsculas
    -- y minúsculas.

    RETURN QUERY
    SELECT p.nombre::text
    FROM pdv p
    INNER JOIN ciudad c
        ON c.idciudad = p.idciudad
    WHERE c.nombre ILIKE p_nombre_ciudad
    ORDER BY p.nombre;
END;
$$;

-- ============================================================================
-- EJERCICIO 4. PRODUCTOS CLASIFICADOS SEGÚN EL PORCENTAJE DE EXCESO
-- Se listan los productos cuyo precio de venta supera el precio básico.
-- El porcentaje se calcula respecto al precio básico y se clasifica en los
-- intervalos indicados en el enunciado.
-- ============================================================================

CREATE OR REPLACE FUNCTION listar_productos_por_exceso()
RETURNS TABLE (
    nomprod text,
    nomfab text,
    preciobasico numeric,
    precioventa numeric,
    cadena_texto text
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- Se descompone el arreglo detalle de cada venta para examinar
    -- cada producto vendido.
    -- Se relacionan los detalles con producto mediante la clave compuesta
    -- (idprod, idfabricante), y con fabricante para obtener sus nombres.
    -- Se calcula el porcentaje de incremento respecto al precio básico.
    -- Los límites se aplican de forma sucesiva para evitar solapamientos.

    RETURN QUERY
    SELECT
        p.nombre::text,
        f.nombre::text,
        p.preciobasico::numeric,
        d.precioventa::numeric,
        'Excede el precio ' ||
        CASE
            WHEN ((d.precioventa - p.preciobasico)
                  / p.preciobasico) * 100 < 10
                THEN 'en menos de 10%'
            WHEN ((d.precioventa - p.preciobasico)
                  / p.preciobasico) * 100 <= 25
                THEN 'entre 10 y 25%'
            WHEN ((d.precioventa - p.preciobasico)
                  / p.preciobasico) * 100 <= 100
                THEN 'entre 25 y 100%'
            WHEN ((d.precioventa - p.preciobasico)
                  / p.preciobasico) * 100 <= 240
                THEN 'entre 100 y 240%'
            ELSE 'en más de 240%'
        END::text
    FROM venta v
    CROSS JOIN LATERAL unnest(v.detalle) AS d
    INNER JOIN producto p
        ON p.idprod = d.idproducto
       AND p.idfabricante = d.idfabricante
    INNER JOIN fabricante f
        ON f.idfabricante = p.idfabricante
    WHERE d.precioventa > p.preciobasico
    ORDER BY p.nombre, f.nombre, d.precioventa;
END;
$$;

-- ============================================================================
-- EJERCICIO 5. GANANCIA INDIVIDUAL DE CADA PRODUCTO VENDIDO
-- Ganancia individual = cantidad * (precio de venta - precio básico - descuento).
-- ============================================================================

CREATE OR REPLACE FUNCTION ganancia_por_venta()
RETURNS TABLE (
    nrofactura integer,
    nomprod text,
    ganancia numeric
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- Se descompone el arreglo detalle para obtener un registro por producto.
    -- Se relaciona cada elemento con producto usando su clave compuesta.
    -- Se calcula la ganancia con la fórmula indicada en el enunciado.

    RETURN QUERY
    SELECT
        v.nrofactura,
        p.nombre::text,
        (
            d.cantidad *
            (d.precioventa - p.preciobasico - d.descuento)
        )::numeric
    FROM venta v
    CROSS JOIN LATERAL unnest(v.detalle) AS d
    INNER JOIN producto p
        ON p.idprod = d.idproducto
       AND p.idfabricante = d.idfabricante
    ORDER BY v.nrofactura, p.nombre;
END;
$$;

-- ============================================================================
-- EJERCICIO 6. GANANCIA TOTAL DE TODAS LAS VENTAS
-- La ganancia total es la suma de las ganancias individuales del ejercicio 5.
-- ============================================================================

CREATE OR REPLACE FUNCTION ganancia_total()
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_total numeric;
BEGIN
    -- Se utiliza la función ganancia_por_venta para obtener las ganancias
    -- individuales y SUM para calcular su suma.
    -- COALESCE devuelve cero cuando todavía no existen ventas.

    SELECT COALESCE(SUM(g.ganancia), 0)
    INTO v_total
    FROM ganancia_por_venta() AS g;

    -- Se devuelve el importe total calculado.
    RETURN v_total;
END;
$$;

-- ============================================================================
-- EJERCICIO 7. TABLA GERENTE QUE HEREDA DE VENDEDOR
-- Se añaden las fechas de inicio y fin del cargo de gerente.
-- ============================================================================

-- La tabla gerente hereda los atributos de vendedor y agrega los campos
-- que permiten registrar el período durante el cual se ocupa el cargo.
-- Se declaran expresamente la clave primaria y las claves foráneas.
-- También se comprueba que la fecha de fin no sea anterior a la de inicio.

CREATE TABLE gerente (
    fecha_inicio_cargo date NOT NULL,
    fecha_fin_cargo date,
    CONSTRAINT pk_gerente PRIMARY KEY (idvendedor),
    CONSTRAINT fk_gerente_pdv
        FOREIGN KEY (idpdv) REFERENCES pdv(idpdv),
    CONSTRAINT fk_gerente_responsable
        FOREIGN KEY (responsable) REFERENCES vendedor(idvendedor),
    CONSTRAINT chk_fechas_gerente
        CHECK (
            fecha_fin_cargo IS NULL
            OR fecha_fin_cargo >= fecha_inicio_cargo
        )
) INHERITS (vendedor);

-- ============================================================================
-- EJERCICIO 8. GERENTES NOMBRADOS DESDE UNA FECHA QUE SIGUEN EN EL CARGO
-- Devuelve el punto de venta, ciudad, región y datos del gerente vigente.
-- ============================================================================

CREATE OR REPLACE FUNCTION gerentes_desde_fecha(p_fecha date)
RETURNS TABLE (
    nombre_pdv text,
    nombre_ciudad text,
    region text,
    nombre_gerente text,
    apellidos_gerente text
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- Se relaciona gerente con pdv para conocer el punto de venta
    -- donde desempeña el cargo cada gerente.
    -- Se relaciona pdv con ciudad para obtener la ciudad y su región.
    -- Se filtran los gerentes cuyo cargo comenzó en la fecha indicada
    -- o después y cuya fecha de fin no existe o todavía no ha vencido.

    RETURN QUERY
    SELECT
        p.nombre::text,
        c.nombre::text,
        c.region::text,
        g.nombre::text,
        g.apellidos::text
    FROM gerente g
    INNER JOIN pdv p
        ON p.idpdv = g.idpdv
    INNER JOIN ciudad c
        ON c.idciudad = p.idciudad
    WHERE g.fecha_inicio_cargo >= p_fecha
      AND (
          g.fecha_fin_cargo IS NULL
          OR g.fecha_fin_cargo >= CURRENT_DATE
      )
    ORDER BY p.nombre, g.apellidos, g.nombre;
END;
$$;

-- ============================================================================
-- EJERCICIO 9. VENDEDORES QUE NO HAN SIDO GERENTES
-- Devuelve los vendedores que no aparecen en la tabla gerente.
-- ============================================================================

CREATE OR REPLACE FUNCTION vendedores_no_gerentes()
RETURNS TABLE (
    id_vendedor integer,
    nombre_vendedor text,
    apellidos_vendedor text,
    id_punto_venta integer
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- ONLY consulta las filas almacenadas directamente en vendedor,
    -- sin incluir automáticamente las filas heredadas de gerente.
    -- NOT EXISTS descarta los vendedores cuyo identificador aparece
    -- en la tabla gerente.
    -- Finalmente, los resultados se ordenan por apellidos y nombre.

    RETURN QUERY
    SELECT
        v.idvendedor,
        v.nombre::text,
        v.apellidos::text,
        v.idpdv
    FROM ONLY vendedor v
    WHERE NOT EXISTS (
        SELECT 1
        FROM gerente g
        WHERE g.idvendedor = v.idvendedor
    )
    ORDER BY v.apellidos, v.nombre;
END;
$$;

-- ============================================================================
-- EJERCICIO 10. VALIDAR QUE LOS PRODUCTOS DE UNA VENTA SEAN VÁLIDOS
-- Se comprueba que cada par producto/fabricante exista en producto.
-- ============================================================================

CREATE OR REPLACE FUNCTION validar_productos_venta()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    elemento tdetalle;
BEGIN
    -- Se comprueba que el arreglo detalle no sea nulo.
    IF NEW.detalle IS NULL THEN
        RAISE EXCEPTION 'El detalle de la venta no puede ser nulo';
    END IF;

    -- Se recorren todos los productos incluidos en el detalle.
    FOREACH elemento IN ARRAY NEW.detalle LOOP
        -- Se valida el producto utilizando ambos campos de su clave primaria.
        IF NOT EXISTS (
            SELECT 1
            FROM producto p
            WHERE p.idprod = elemento.idproducto
              AND p.idfabricante = elemento.idfabricante
        ) THEN
            -- Si no existe, se cancela la inserción o modificación de la venta.
            RAISE EXCEPTION
                'El producto % del fabricante % no existe',
                elemento.idproducto,
                elemento.idfabricante;
        END IF;
    END LOOP;

    -- Si todos los productos son válidos, se permite continuar.
    RETURN NEW;
END;
$$;

-- Se elimina el disparador anterior si existía y se crea nuevamente.
DROP TRIGGER IF EXISTS trg_validar_productos_venta ON venta;

CREATE TRIGGER trg_validar_productos_venta
BEFORE INSERT OR UPDATE OF detalle ON venta
FOR EACH ROW
EXECUTE FUNCTION validar_productos_venta();

-- ============================================================================
-- EJERCICIO 11. EXIGIR UNA GANANCIA MÍNIMA DEL 5 %
-- El precio de venta debe ser mayor o igual que el precio básico multiplicado
-- por 1.05, tal como establece la condición del enunciado.
-- ============================================================================

CREATE OR REPLACE FUNCTION validar_ganancia_minima()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    elemento tdetalle;
    precio_base numeric;
BEGIN
    -- Se recorren los productos incluidos en el detalle de la venta.
    FOREACH elemento IN ARRAY NEW.detalle LOOP
        -- Se consulta el precio básico del producto correspondiente.
        SELECT p.preciobasico
        INTO precio_base
        FROM producto p
        WHERE p.idprod = elemento.idproducto
          AND p.idfabricante = elemento.idfabricante;

        -- Se rechaza el producto si no se encuentra el precio básico,
        -- si el precio de venta es nulo o si no alcanza el 105 % del básico.
        IF precio_base IS NULL
           OR elemento.precioventa IS NULL
           OR elemento.precioventa < precio_base * 1.05
        THEN
            RAISE EXCEPTION
                'El producto % no cumple con la ganancia mínima del 5 por ciento',
                elemento.idproducto;
        END IF;
    END LOOP;

    -- Si todos los productos cumplen la condición, se permite continuar.
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_ganancia_minima ON venta;

CREATE TRIGGER trg_validar_ganancia_minima
BEFORE INSERT OR UPDATE OF detalle ON venta
FOR EACH ROW
EXECUTE FUNCTION validar_ganancia_minima();

-- ============================================================================
-- EJERCICIO 12. IMPEDIR LA VENTA EN DIVISA DE PRODUCTOS ALCATEL
-- ============================================================================

CREATE OR REPLACE FUNCTION validar_venta_alcatel_divisa()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    elemento tdetalle;
    fabricante_producto text;
BEGIN
    -- La comprobación solo se realiza cuando la venta está marcada en divisa.
    IF NEW.divisa = TRUE THEN
        -- Se recorren los productos incluidos en el detalle de la venta.
        FOREACH elemento IN ARRAY NEW.detalle LOOP
            -- Se obtiene el nombre del fabricante de cada producto.
            SELECT f.nombre
            INTO fabricante_producto
            FROM producto p
            INNER JOIN fabricante f
                ON f.idfabricante = p.idfabricante
            WHERE p.idprod = elemento.idproducto
              AND p.idfabricante = elemento.idfabricante;

            -- Si el fabricante contiene el nombre Alcatel, se rechaza la venta.
            IF fabricante_producto ILIKE '%Alcatel%' THEN
                RAISE EXCEPTION
                    'No se permite vender productos Alcatel en moneda extranjera';
            END IF;
        END LOOP;
    END IF;

    -- Si no se infringe la condición, se permite continuar.
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_alcatel_divisa ON venta;

CREATE TRIGGER trg_validar_alcatel_divisa
BEFORE INSERT OR UPDATE OF detalle, divisa ON venta
FOR EACH ROW
EXECUTE FUNCTION validar_venta_alcatel_divisa();

-- ============================================================================
-- EJERCICIO 13. RESPONSABLES DIRECTOS E INDIRECTOS DE UN VENDEDOR
-- La jerarquía se recorre en sentido ascendente: primero el responsable
-- directo y después los responsables de los niveles superiores.
-- ============================================================================

CREATE OR REPLACE FUNCTION responsables_vendedor(p_idvendedor integer)
RETURNS TABLE (
    id_responsable integer,
    nombre_responsable text,
    apellidos_responsable text,
    nivel_jerarquico integer
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- Se crea una lista de vendedores sin identificadores repetidos.
    -- La consulta incluye los registros heredados de gerente.

    RETURN QUERY
    WITH RECURSIVE vendedores_unicos AS MATERIALIZED (
        SELECT DISTINCT ON (v.idvendedor)
            v.idvendedor,
            v.nombre,
            v.apellidos,
            v.responsable
        FROM vendedor v
        ORDER BY v.idvendedor
    ),

    -- El vendedor recibido como parámetro constituye el nivel inicial (0).
    -- Se guarda también el recorrido realizado para detectar posibles ciclos.
    jerarquia AS (
        SELECT
            v.idvendedor,
            v.nombre,
            v.apellidos,
            v.responsable,
            0 AS nivel,
            ARRAY[v.idvendedor] AS camino
        FROM vendedores_unicos v
        WHERE v.idvendedor = p_idvendedor

        UNION ALL

        -- Se localiza el responsable del vendedor del nivel anterior.
        -- El nivel aumenta en uno en cada paso de la recursión.
        SELECT
            r.idvendedor,
            r.nombre,
            r.apellidos,
            r.responsable,
            j.nivel + 1,
            j.camino || r.idvendedor
        FROM jerarquia j
        INNER JOIN vendedores_unicos r
            ON r.idvendedor = j.responsable

        -- Se impide visitar nuevamente un identificador ya recorrido.
        WHERE NOT (r.idvendedor = ANY(j.camino))
    )

    -- Se excluye el vendedor inicial y se devuelven sus responsables,
    -- ordenados desde el nivel más cercano hasta el superior.
    SELECT
        j.idvendedor,
        j.nombre::text,
        j.apellidos::text,
        j.nivel
    FROM jerarquia j
    WHERE j.nivel > 0
    ORDER BY j.nivel;
END;
$$;

-- ============================================================================
-- EJERCICIO 14. APLANAR LAS VENTAS Y CALCULAR TOTALES Y SUBTOTALES
-- Primera función: convierte cada elemento del arreglo detalle en una fila.
-- Segunda función: calcula los totales por año y punto de venta, los subtotales
-- por año, los subtotales por punto de venta y el gran total.
-- ============================================================================

CREATE OR REPLACE FUNCTION listartodaslasventas()
RETURNS TABLE (
    idvendedor integer,
    idcliente integer,
    nrofactura integer,
    divisa boolean,
    fechahora timestamp,
    idproducto integer,
    idfabricante integer,
    cantidad numeric,
    descuento numeric,
    precioventa numeric
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- Se recorren las ventas y se descompone el arreglo detalle.
    -- Cada fila resultante representa un producto de una factura.

    RETURN QUERY
    SELECT
        v.idvendedor,
        v.idcliente,
        v.nrofactura,
        v.divisa,
        v.fechahora,
        d.idproducto,
        d.idfabricante,
        d.cantidad,
        d.descuento,
        d.precioventa
    FROM venta v
    CROSS JOIN LATERAL unnest(v.detalle) AS d;
END;
$$;

CREATE OR REPLACE FUNCTION informe_ventas_por_anio_pdv()
RETURNS TABLE (
    anio integer,
    id_pdv integer,
    nombre_pdv text,
    total_ventas numeric,
    tipo_resumen text
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- Se crea una relación de vendedores sin identificadores repetidos.
    -- La consulta a vendedor incluye los registros heredados de gerente.
    -- Esto permite considerar ventas realizadas por vendedores o gerentes.

    RETURN QUERY
    WITH vendedores_unicos AS MATERIALIZED (
        SELECT DISTINCT ON (v.idvendedor)
            v.idvendedor,
            v.idpdv
        FROM vendedor v
        ORDER BY v.idvendedor
    ),

    -- Se obtiene el año de cada venta, el punto de venta correspondiente
    -- y el importe de los productos vendidos (cantidad por precio de venta).
    datos AS (
        SELECT
            EXTRACT(YEAR FROM l.fechahora)::integer AS anio,
            p.idpdv,
            p.nombre::text AS nombre_pdv,
            l.cantidad * l.precioventa AS importe
        FROM listartodaslasventas() l
        INNER JOIN vendedores_unicos v
            ON v.idvendedor = l.idvendedor
        INNER JOIN pdv p
            ON p.idpdv = v.idpdv
    )

    -- GROUPING SETS genera los cuatro niveles solicitados:
    -- (año, punto de venta), (año), (punto de venta) y gran total.
    SELECT
        d.anio,
        d.idpdv,
        d.nombre_pdv,
        COALESCE(SUM(d.importe), 0)::numeric,
        CASE
            WHEN GROUPING(d.anio) = 0
             AND GROUPING(d.idpdv) = 0
                THEN 'Total por año y punto de venta'
            WHEN GROUPING(d.anio) = 0
             AND GROUPING(d.idpdv) = 1
                THEN 'Subtotal por año'
            WHEN GROUPING(d.anio) = 1
             AND GROUPING(d.idpdv) = 0
                THEN 'Subtotal por punto de venta'
            ELSE 'Gran total'
        END::text
    FROM datos d
    GROUP BY GROUPING SETS (
        (d.anio, d.idpdv, d.nombre_pdv),
        (d.anio),
        (d.idpdv, d.nombre_pdv),
        ()
    )
    ORDER BY
        GROUPING(d.anio),
        d.anio NULLS LAST,
        GROUPING(d.idpdv),
        d.idpdv NULLS LAST;
END;
$$;

-- ============================================================================
-- DATOS DE PRUEBA UTILIZADOS EN LAS COMPROBACIONES
-- IMPORTANTE: insertar estos datos solamente en un esquema vacío.
-- Las ventas cumplen las tres validaciones: producto existente, precio de
-- venta >= 105% del precio básico y Alcatel no vendido en divisa.
-- ============================================================================

INSERT INTO ciudad (idciudad, nombre, region) VALUES
    (9901, 'Santa Clara', 'Centro'),
    (9902, 'Santo Domingo', 'Centro');

INSERT INTO cliente (idcliente, nombre, apellidos, direccion) VALUES
    (9901, 'Ana', 'Pérez', NULL),
    (9902, 'Luis', 'García', NULL);

INSERT INTO fabricante (idfabricante, nombre) VALUES
    (9901, 'Alcatel'),
    (9902, 'Samsung');

INSERT INTO pdv (idpdv, planventas_real, nombre, direccion, idciudad) VALUES
    (9901, 50000, 'PDV Santa Clara', NULL, 9901),
    (9902, 60000, 'PDV Santo Domingo', NULL, 9902);

INSERT INTO producto (idprod, idfabricante, nombre, um, preciobasico) VALUES
    (9901, 9901, 'Teléfono Alcatel', 'unidad', 100),
    (9902, 9902, 'Teléfono Samsung', 'unidad', 100);

INSERT INTO vendedor
    (idvendedor, planventasreal, nombre, apellidos, direccion, idpdv, responsable)
VALUES
    (9901, 10000, 'Carlos', 'Rodríguez', NULL, 9901, NULL),
    (9903, 12000, 'María', 'López', NULL, 9902, 9901);

-- Pedro Martínez es gerente y responsable de María López.
-- La fila se inserta en gerente, que hereda los atributos de vendedor.
INSERT INTO gerente
    (idvendedor, planventasreal, nombre, apellidos, direccion, idpdv,
     responsable, fecha_inicio_cargo, fecha_fin_cargo)
VALUES
    (9902, 15000, 'Pedro', 'Martínez', NULL, 9901, 9903,
     DATE '2025-01-01', NULL);

-- Factura 99001: producto Alcatel en moneda nacional (CUP).
-- Cantidad 2, descuento 5 y precio de venta 120; ganancia = 30.
INSERT INTO venta
    (nrofactura, idvendedor, idcliente, divisa, fechahora, detalle)
VALUES
    (99001, 9901, 9901, FALSE, TIMESTAMP '2026-01-15 10:00:00',
     ARRAY[ROW(9901, 9901, 2, 5, 120)::tdetalle]);

-- Factura 99002: producto Samsung en divisa.
-- Cantidad 3, descuento 10 y precio de venta 130; ganancia = 60.
INSERT INTO venta
    (nrofactura, idvendedor, idcliente, divisa, fechahora, detalle)
VALUES
    (99002, 9903, 9902, TRUE, TIMESTAMP '2026-02-20 11:30:00',
     ARRAY[ROW(9902, 9902, 3, 10, 130)::tdetalle]);

-- ============================================================================
-- CONSULTAS DE COMPROBACIÓN
-- Ejecutar después de insertar datos válidos en las tablas.
-- Si las tablas están vacías, algunas consultas devolverán cero filas y
-- ganancia_total() devolverá 0.
-- ============================================================================

-- Ejercicio 1
SELECT typname AS nombre_tipo
FROM pg_type
WHERE typnamespace = 'punto_de_venta'::regnamespace
  AND typname IN (
      'tdireccion',
      'tdetalle',
      'tciudad',
      'tcliente',
      'tfabricante',
      'tpdv',
      'tproducto',
      'tvendedor',
      'tventa'
  )
ORDER BY typname;

-- Ejercicio 2
SELECT table_name AS nombre_tabla,
       table_type AS tipo
FROM information_schema.tables
WHERE table_schema = 'punto_de_venta'
ORDER BY table_name;

-- Ejercicio 3
SELECT * FROM pdv_por_ciudad('Santa Clara');

-- Ejercicio 4
SELECT * FROM listar_productos_por_exceso();

-- Ejercicio 5
SELECT * FROM ganancia_por_venta();

-- Ejercicio 6
SELECT ganancia_total();

-- Ejercicio 7
SELECT * FROM punto_de_venta.gerente;

-- Ejercicio 8
SELECT * FROM gerentes_desde_fecha(DATE '2024-01-01');

-- Ejercicio 9
SELECT * FROM vendedores_no_gerentes();

-- Ejercicio 10
SELECT tgname AS nombre_trigger,
       CASE
           WHEN tgenabled = 'O' THEN 'Activo'
           ELSE 'No activo'
       END AS estado
FROM pg_trigger
WHERE tgrelid = 'punto_de_venta.venta'::regclass
  AND NOT tgisinternal
  AND tgname = 'trg_validar_productos_venta';

-- Ejercicio 11
SELECT tgname AS nombre_trigger,
       CASE
           WHEN tgenabled = 'O' THEN 'Activo'
           ELSE 'No activo'
       END AS estado
FROM pg_trigger
WHERE tgrelid = 'punto_de_venta.venta'::regclass
  AND NOT tgisinternal
  AND tgname = 'trg_validar_ganancia_minima';

-- Ejercicio 12
SELECT tgname AS nombre_trigger,
       CASE
           WHEN tgenabled = 'O' THEN 'Activo'
           ELSE 'No activo'
       END AS estado
FROM pg_trigger
WHERE tgrelid = 'punto_de_venta.venta'::regclass
  AND NOT tgisinternal
  AND tgname = 'trg_validar_alcatel_divisa';

-- Ejercicio 13
SELECT * FROM responsables_vendedor(9902);

-- Ejercicio 14
SELECT * FROM listartodaslasventas();
SELECT * FROM informe_ventas_por_anio_pdv();
